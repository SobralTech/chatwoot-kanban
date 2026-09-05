# rubocop:disable Metrics/ClassLength
class Webhooks::WahaEventsJob < ApplicationJob
  # Live inbound WhatsApp traffic, on the same queue as the other realtime channel
  # webhooks. It must not sit on :low, which is the lowest-priority queue and also
  # carries the bulk history-import work — an import would delay every incoming
  # message behind it.
  queue_as :default

  # A delivery ack can arrive while the mirror (message.any) is still being
  # created — creating it takes ~1s (contact/conversation resolution) while the
  # ack is processed in milliseconds. We retry the ack a few times so it lands
  # after the message exists instead of being dropped.
  ACK_MAX_RETRIES = 3
  ACK_RETRY_DELAY = 3.seconds

  # A live media download can hit a transient WAHA/network blip. MAX_ATTEMPTS
  # counts the original try (2 retries) before the event gives up retrying and
  # persists the message with a visible fallback instead — mirrors
  # Waha::SendOnWahaService's send-side retry budget/backoff.
  MEDIA_MAX_ATTEMPTS = 3
  MEDIA_RETRY_DELAYS = [10.seconds, 60.seconds].freeze

  def perform(channel_id, params = {}, ack_retries = 0, media_attempt = 1)
    channel = Channel::Waha.find_by(id: channel_id)
    return unless channel&.account&.active?
    return if invalid_webhook_session?(channel, params)

    route_event(channel, params, ack_retries, media_attempt)
  end

  private

  # The controller rejects missing or mismatched sessions before enqueueing. The
  # repeat check protects retries and jobs enqueued before a channel was edited.
  def invalid_webhook_session?(channel, params)
    error = channel.webhook_error(params['session'])
    return false unless error

    Rails.logger.warn "[WAHA] Ignored webhook for channel #{channel.id}: #{error}"
    true
  end

  # We subscribe to message.any only (the superset of every message event) so
  # each message is processed exactly once, regardless of direction.
  def route_event(channel, params, ack_retries, media_attempt)
    case params['event'].to_s
    when 'message.any'
      handle_message(channel, params, media_attempt)
    when 'message.ack', 'message.ack.group'
      handle_message_ack(channel, params, ack_retries)
    when 'message.edited', 'message.revoked', 'message.reaction'
      handle_message_mutation(channel, params, ack_retries, media_attempt)
    when 'poll.vote'
      handle_poll_vote(channel, params, ack_retries)
    when *Waha::CallEventService::EVENT_RESULTS.keys
      handle_call(channel, params)
    when 'session.status'
      handle_session_status(channel, params['payload'])
    else
      Rails.logger.warn "[WAHA] Ignored unsupported webhook event channel=#{channel.id} inbox=#{channel.inbox.id} event=#{params['event']}"
    end
  end

  def handle_call(channel, params)
    payload = params['payload'].presence || {}

    Waha::CallEventService.new(channel: channel, event: params['event'], payload: payload).perform
  end

  # Share the persistence lock with incoming/history messages. Resolving the
  # family head and migrating/removing reactions must be in the same transaction.
  def handle_message_mutation(channel, params, retries, media_attempt)
    payload = params['payload']
    return if payload.blank?

    source_id = mutation_source_id(payload)
    return if source_id.blank?

    chat_jid = mutation_chat_jid(payload, source_id)
    target = find_message_by_source_id(channel, source_id, chat_jid)
    chat_jids = [chat_jid]
    chat_jids << target.conversation.contact_inbox&.source_id if target
    Waha::Locking.with_chat_lock(channel, chat_jids) do
      dispatch_message_mutation(channel, params, retries, media_attempt)
    end
  rescue StandardError => e
    raise unless params['event'] == 'message.revoked'

    retry_event(channel, params, retries, reason: e.class.name)
  end

  def mutation_source_id(payload)
    payload['editedMessageId'] || payload['revokedMessageId'] || payload.dig('before', 'id') || payload.dig('reaction', 'messageId') ||
      payload.dig('poll', 'id')
  end

  # GOWS emits a poll vote separately from message.any. The vote must find the
  # creation message first, so a race with the poll webhook is retried through
  # the same bounded, observable path as edits, reactions and acknowledgements.
  def handle_poll_vote(channel, params, retries)
    applied = Waha::PollVoteApplier.new(channel: channel, payload: params['payload'] || {}).perform
    retry_event(channel, params, retries) unless applied
  end

  def dispatch_message_mutation(channel, params, retries, media_attempt)
    case params['event']
    when 'message.edited' then handle_message_edited(channel, params, retries, media_attempt)
    when 'message.revoked' then handle_message_revoked(channel, params, retries)
    when 'message.reaction' then handle_message_reaction(channel, params, retries)
    end
  end

  def mutation_chat_jid(payload, source_id)
    envelope = payload['after'] || payload
    jid = Waha::Anchoring.chat_jid_of(source_id) || Waha::Anchoring.chat_jid_of(envelope['id']) ||
          envelope.dig('_data', 'Info', 'Chat') || (envelope['fromMe'] ? envelope['to'] : envelope['from'])
    Waha::Jid.phone_jid(jid) || jid
  end

  def handle_message(channel, params, media_attempt)
    payload = params['payload']
    return if payload.blank?
    # A fromMe event WAHA can trace back to a specific Chatwoot send (its id
    # matches that attempt's pre-generated or confirmed id) is the echo of our
    # own request; absorb it here and settle the attempt if it hasn't been yet
    # (the echo can race ahead of our HTTP response).
    return if suppress_chatwoot_echo?(channel, payload)

    # Incoming from a contact (fromMe: false), sent from the phone/WhatsApp app
    # directly, or sent by another system sharing this WAHA session (fromMe:
    # true, uncorrelated) — mirror all of these into Chatwoot; the service's own
    # dedup check is the single gate against double-mirroring.
    Waha::IncomingMessageService.new(channel: channel, payload: payload).perform
  rescue CustomExceptions::Waha::MediaDownloadError => e
    retry_media_or_finalize(channel, params, media_attempt, e) do
      Waha::IncomingMessageService.new(channel: channel, payload: payload, media_terminal: true).perform
    end
  end

  def suppress_chatwoot_echo?(channel, payload)
    return false unless payload['fromMe']

    attempt = WahaDeliveryAttempt.find_by_correlated_id(channel: channel, wa_message_id: payload['id'])
    return false unless attempt

    attempt.confirm_sent!(payload['id'])
    true
  end

  # Maps WhatsApp delivery receipts onto Chatwoot statuses so outgoing bubbles
  # show the right check state (sent → delivered → read), mirroring WhatsApp
  # itself. GOWS splits them in two: `message.ack` for direct chats and
  # `message.ack.group` for per-participant group receipts.
  def handle_message_ack(channel, params, retries)
    applied = Waha::AckApplier.new(
      channel: channel, payload: params['payload'] || {}, group: params['event'] == 'message.ack.group'
    ).perform
    # The mirror is likely still being created — retry so we don't drop the ack.
    retry_event(channel, params, retries) unless applied
  end

  # The mirror may still be being created (contact/conversation resolution takes
  # ~1s while the event lands in milliseconds), so replay the event a few times
  # before giving up on it.
  def retry_event(channel, params, retries, reason: 'missing_anchor')
    context = "channel=#{channel.id} inbox=#{channel.inbox.id} event=#{params['event']} retry=#{retries} reason=#{reason}"
    payload = params['payload'] || {}
    context += " source_id=#{mutation_source_id(payload) || payload['id']}"
    if retries >= ACK_MAX_RETRIES
      Rails.logger.error "[WAHA] Event retries exhausted #{context}"
      return
    end

    Rails.logger.warn "[WAHA] Event retry scheduled #{context} delay=#{ACK_RETRY_DELAY.to_i}s"
    self.class.set(wait: ACK_RETRY_DELAY).perform_later(channel.id, params, retries + 1)
  end

  # A WhatsApp edit keeps the original in place; instead we post the new content
  # as a fresh message quoting the original, then strike the original through
  # (superseded flag, rendered as line-through) — the "[✏️ Editada]" marker.
  # The new version must exist before anything is struck: if persisting it
  # raises, the original is never touched and stays intact and visible. Agent
  # edits made from Chatwoot round-trip through this same event (fromMe: true).
  def handle_message_edited(channel, params, retries, media_attempt)
    payload = params['payload']
    return if payload.blank?

    original = find_message_by_source_id(channel, payload['editedMessageId'], mutation_chat_jid(payload, payload['editedMessageId']))
    # The base message can still be mid-creation (message.any resolves
    # contact/conversation before this arrives) or simply not delivered yet —
    # replay the event instead of mirroring the edit as an unanchored message.
    return retry_event(channel, params, retries) if original.nil?
    return if original.content_attributes['deleted']

    edited = Waha::IncomingMessageService.new(channel: channel, payload: payload, edited_original: original).perform
    supersede_edit_family(channel, original, except: edited) if edited
  rescue CustomExceptions::Waha::MediaDownloadError => e
    retry_media_or_finalize(channel, params, media_attempt, e) do
      edited = Waha::IncomingMessageService.new(channel: channel, payload: payload, edited_original: original, media_terminal: true).perform
      supersede_edit_family(channel, original, except: edited) if edited
    end
  end

  # A transient media-download failure keeps the whole event retryable instead
  # of persisting an incomplete message that would block recovery via dedup
  # (the message is never created until the download either succeeds or is
  # explicitly given up on). Once MEDIA_MAX_ATTEMPTS is reached, the block
  # persists the message anyway with Waha::MediaAttacher's visible fallback.
  def retry_media_or_finalize(channel, params, media_attempt, error)
    if media_attempt < MEDIA_MAX_ATTEMPTS
      Rails.logger.warn "[WAHA] Transient media download failure (attempt #{media_attempt}): #{error.message}"
      self.class.set(wait: MEDIA_RETRY_DELAYS[media_attempt - 1]).perform_later(channel.id, params, 0, media_attempt + 1)
    else
      Rails.logger.error "[WAHA] Media download exhausted retries, using visible fallback: #{error.message}"
      yield
    end
  end

  # WhatsApp keeps a single message across N edits (all pointing at the original
  # stanza), but we mirror each edit as a fresh message. So on every edit we
  # strike through the whole prior family — the original plus any earlier edit
  # mirrors — leaving only the just-persisted version un-struck as the current
  # one. Called only once that version exists, so a failure before this point
  # never leaves the family without an un-struck head.
  def supersede_edit_family(channel, original, except:)
    edit_family(channel, original.source_id).where.not(id: except.id).find_each { |message| mark_superseded(message) }
  end

  def mark_superseded(message)
    return if message.additional_attributes['superseded']

    message.update!(additional_attributes: message.additional_attributes.merge('superseded' => true))
  end

  # A revoke ("delete for everyone") removes the message on WhatsApp, so we
  # soft-delete the whole edit family — the original plus any edit mirrors —
  # since all versions disappear at once there. Deletes made from Chatwoot
  # round-trip through this same event; already-deleted messages are skipped,
  # which makes the round-trip idempotent.
  def handle_message_revoked(channel, params, retries)
    payload = params['payload']
    source_id = payload['revokedMessageId'] || payload.dig('before', 'id')
    revoked = find_message_by_source_id(channel, source_id, mutation_chat_jid(payload, source_id))
    return retry_event(channel, params, retries) unless revoked

    edit_family(channel, Waha::Anchoring.anchor_source_id(revoked)).find_each { |message| soft_delete_message(message) }
  end

  def edit_family(channel, anchor_source_id)
    Waha::Anchoring.family(channel.inbox, anchor_source_id)
  end

  # Applies a WhatsApp reaction to the mirrored message. Reactions sent from
  # Chatwoot (fromMe + source: 'api') are processed too: like edits, the UI is
  # rebuilt from the returning webhook instead of being applied locally.
  def handle_message_reaction(channel, params, retries)
    payload = params['payload']
    source_id = payload.dig('reaction', 'messageId')
    target = find_message_by_source_id(channel, source_id, mutation_chat_jid(payload, source_id))

    # The base can still be in flight, just like an ack's target.
    return retry_event(channel, params, retries) if target.nil?

    Waha::ReactionApplier.new(channel: channel, target_message: current_family_member(channel, target), payload: payload).perform
  end

  # Reactions are displayed on the current (un-struck) member of the edit family,
  # not necessarily on the anchor the webhook points at.
  def current_family_member(channel, message)
    edit_family(channel, Waha::Anchoring.anchor_source_id(message))
      .where("COALESCE(additional_attributes->>'superseded', 'false') = 'false'").first || message
  end

  def soft_delete_message(message)
    return if message.content_attributes['deleted']

    ActiveRecord::Base.transaction do
      message.update!(
        content: I18n.t('conversations.messages.deleted'),
        content_type: :text,
        content_attributes: message.content_attributes.except('reactions').merge('deleted' => true)
      )
      message.attachments.each(&:destroy!)
    end
  end

  def handle_session_status(channel, payload)
    status = payload&.dig('status')
    return if status.blank?

    unless status == 'WORKING'
      channel.update_session_status(status)
      return
    end

    # One session fetch serves both the mismatch check and the number lock below.
    number = connected_number(channel)
    return if block_number_mismatch?(channel, number)

    channel.update_session_status(status)
    register_connected_number(channel, number)
    trigger_history_import(channel)
  end

  # On WORKING we either run the opt-in initial import (once, consuming the
  # setup choice) or an automatic reconnect gap-fill. gap_fill_window returns nil
  # on the first ever connection (no prior outage), so nothing runs there.
  def trigger_history_import(channel)
    months = channel.consume_import_on_connect_months!
    return start_history_import(channel, channel.initial_import_window(months), 'initial') if months

    window = channel.gap_fill_window
    start_history_import(channel, window, 'gap_fill') if window
  end

  def start_history_import(channel, window, kind)
    channel.enqueue_history_import!(window, kind: kind)
  end

  # On the first successful connection we adopt the real number reported by WAHA
  # (overriding the free-typed value entered at creation) and lock it as the
  # canonical reference for future reconnections.
  def register_connected_number(channel, number)
    return if channel.connected_number_locked? || number.blank?

    channel.update!(phone_number: number, connected_number_locked: true)
  end

  # Once a number is locked, a reconnection with a different number is refused:
  # we log out immediately, keep phone_number intact and record a synthetic event
  # the frontend surfaces as a blocked mismatch.
  def block_number_mismatch?(channel, number)
    return false unless channel.connected_number_locked?
    return false if number.blank? || number == channel.phone_number

    Waha::SessionService.new(channel: channel).logout
    channel.log_status_event('NUMBER_MISMATCH_BLOCKED')
    true
  end

  # WAHA returns the connected account under me.id (e.g. "5562...@c.us"); we
  # compare/store it as digits only.
  def connected_number(channel)
    session_info = Waha::SessionService.new(channel: channel).status
    session_info&.dig('me', 'id').to_s.gsub(/\D/, '').presence
  end

  def find_message_by_source_id(channel, source_id, chat_jid = nil)
    Waha::Anchoring.find_message(channel, source_id, chat_jid)
  end
end
# rubocop:enable Metrics/ClassLength
