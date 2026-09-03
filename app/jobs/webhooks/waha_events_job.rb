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

  def perform(channel_id, params = {}, ack_retries = 0)
    channel = Channel::Waha.find_by(id: channel_id)
    return unless channel&.account&.active?

    route_event(channel, params, ack_retries)
  end

  private

  # We subscribe to message.any only (the superset of every message event) so
  # each message is processed exactly once, regardless of direction.
  def route_event(channel, params, ack_retries)
    case params['event'].to_s
    when 'message.any'
      handle_message(channel, params['payload'])
    when 'message.ack'
      handle_message_ack(channel, params, ack_retries)
    when 'message.edited'
      handle_message_edited(channel, params['payload'])
    when 'message.revoked'
      handle_message_revoked(channel, params['payload'])
    when 'message.reaction'
      handle_message_reaction(channel, params, ack_retries)
    when 'session.status'
      handle_session_status(channel, params['payload'])
    end
  end

  def handle_message(channel, payload)
    return if payload.blank?
    # Sent from Chatwoot via the WAHA API — the local message already exists (with
    # its source_id). Mirroring would duplicate it; acks drive its status.
    return if chatwoot_originated?(payload)

    # Incoming from a contact (fromMe: false) or sent from the phone/WhatsApp app
    # directly (fromMe: true, source: app/web). Mirror both into Chatwoot; the
    # service's own dedup check is the single gate against double-mirroring.
    Waha::IncomingMessageService.new(channel: channel, payload: payload).perform
  end

  def chatwoot_originated?(payload)
    payload['fromMe'] && payload['source'] == 'api'
  end

  # Maps WhatsApp delivery acks to Chatwoot statuses so outgoing bubbles show the
  # right check state (sent → delivered → read), mirroring WhatsApp itself.
  def handle_message_ack(channel, params, retries)
    payload = params['payload']
    message = find_message_by_source_id(channel, payload&.dig('id'))
    return update_delivery_status(message, payload&.dig('ack')) if message

    # The mirror is likely still being created — retry so we don't drop the ack.
    retry_event(channel, params, retries)
  end

  # The mirror may still be being created (contact/conversation resolution takes
  # ~1s while the event lands in milliseconds), so replay the event a few times
  # before giving up on it.
  def retry_event(channel, params, retries)
    return if retries >= ACK_MAX_RETRIES

    self.class.set(wait: ACK_RETRY_DELAY).perform_later(channel.id, params, retries + 1)
  end

  def update_delivery_status(message, ack)
    return unless message&.outgoing?

    new_status = ack_to_status(ack)
    return if new_status.nil? || status_downgrade?(message.status, new_status)

    message.update!(status: new_status)
  end

  def ack_to_status(ack)
    case ack
    when -1 then 'failed'
    when 1 then 'sent'
    when 2 then 'delivered'
    when 3, 4 then 'read'
    end
  end

  # Acks can arrive out of order; never move a message backwards (e.g. read → delivered).
  def status_downgrade?(current, new_status)
    return false if new_status == 'failed'

    rank = { 'sent' => 1, 'delivered' => 2, 'read' => 3 }
    rank.fetch(new_status, 0) <= rank.fetch(current, 0)
  end

  # A WhatsApp edit keeps the original in place; instead we strike the original
  # through (superseded flag, rendered as line-through) and post the new content
  # as a fresh message quoting the original — the "[✏️ Editada]" marker. Agent
  # edits made from Chatwoot round-trip through this same event (fromMe: true).
  def handle_message_edited(channel, payload)
    return if payload.blank?

    original = find_message_by_source_id(channel, payload['editedMessageId'])
    supersede_edit_family(channel, original) if original
    Waha::IncomingMessageService.new(channel: channel, payload: payload, edited_original: original).perform
  end

  # WhatsApp keeps a single message across N edits (all pointing at the original
  # stanza), but we mirror each edit as a fresh message. So on every edit we
  # strike through the whole prior family — the original plus any earlier edit
  # mirrors — leaving only the newest version un-struck as the current one.
  def supersede_edit_family(channel, original)
    edit_family(channel, original.source_id).find_each { |message| mark_superseded(message) }
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
  def handle_message_revoked(channel, payload)
    return if payload.blank?

    revoked = find_message_by_source_id(channel, payload['revokedMessageId'] || payload.dig('before', 'id'))
    return unless revoked

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
    target = find_message_by_source_id(channel, payload&.dig('reaction', 'messageId'))

    # A missing target is the same race as acks; after the retries it drops
    # silently (a reaction to a message older than the inbox).
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
        content_attributes: message.content_attributes.merge('deleted' => true)
      )
      message.attachments.destroy_all
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

  def find_message_by_source_id(channel, source_id)
    Waha::Anchoring.by_stanza(channel.inbox, source_id).first
  end
end
