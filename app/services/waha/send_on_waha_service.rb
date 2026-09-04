# rubocop:disable Metrics/ClassLength
class Waha::SendOnWahaService < Base::SendOnChannelService
  TYPING_PRESENCE_QUEUE_WAIT_LIMIT = 20_000

  # Retries apply only to CustomExceptions::Waha::TransientError (5xx, timeout,
  # connection failure). MAX_SEND_ATTEMPTS counts the original try, so this
  # allows 2 retries before the message is marked failed for good. Counted off
  # WahaDeliveryAttempt#attempt_count (persisted), not a job argument, so it
  # survives a crash between send and confirmation.
  MAX_SEND_ATTEMPTS = 3
  RETRY_DELAYS = [10.seconds, 60.seconds].freeze

  # How far back to look, in a chat's own message list, for a message carrying
  # our pre-generated id when a send's outcome is unknown (see
  # #reconcile_ambiguous_dispatch!).
  RECONCILIATION_LOOKBACK = 20

  pattr_initialize [:message!, :skip_presence]

  private

  def channel_class
    Channel::Waha
  end

  def perform_reply
    send_seen

    if skip_presence
      pause_presence
      deliver_message
    elsif clock_enabled?
      reserve_and_queue_delivery
    else
      deliver_message
    end
  rescue CustomExceptions::Waha::TransientError => e
    handle_transient_failure(e)
  rescue StandardError => e
    fail_message!(e)
  end

  # Claims the persisted attempt (a no-op if another execution is already
  # sending), assigns a WAHA-generated id up front when the engine supports it,
  # and confirms the send atomically once WAHA responds with a message id.
  def deliver_message
    return unless delivery_attempt.claim!

    ensure_client_message_id!
    delivery_attempt.update!(dispatched_at: Time.current)

    result = attachment ? send_attachment : send_text
    return release_attempt! if result.nil?

    wa_message_id = result.is_a?(Hash) ? result['id'] : nil
    raise CustomExceptions::Waha::ApiError, 'WAHA accepted the request but returned no message id' if wa_message_id.blank?

    delivery_attempt.confirm_sent!(wa_message_id)
  end

  # WAHA's pre-generated id is the closest thing GOWS offers to a client-defined
  # idempotency key (see MessageTextRequest#id upstream): reused across retries
  # of the same message, it lets a correlated fromMe echo or a reconciliation
  # scan confirm a send whose HTTP response never came back. Some engines don't
  # support the endpoint; that's a documented, observable limitation, not a
  # reason to fail the send.
  def ensure_client_message_id!
    return if delivery_attempt.client_message_id.present?

    id = fetch_client_message_id
    delivery_attempt.update!(client_message_id: id) if id.present?
  end

  def fetch_client_message_id
    http_client.get("#{channel.session_name}/new-message-id")['id']
  rescue CustomExceptions::Waha::TransientError
    raise
  rescue CustomExceptions::Waha::ApiError => e
    Rails.logger.warn "[WAHA] engine does not support pre-generated message ids for message #{message.id}: #{e.message}"
    nil
  end

  # An attachment we can't resolve a URL for leaves nothing to retry towards, so
  # release the claim instead of leaving the attempt stuck in `sending` forever.
  def release_attempt!
    delivery_attempt.update!(status: :pending)
    nil
  end

  def handle_transient_failure(error)
    return if reconcile_ambiguous_dispatch!

    if delivery_attempt.attempt_count < MAX_SEND_ATTEMPTS
      return unless delivery_attempt.release_to_pending!

      Rails.logger.warn "[WAHA] Transient send failure for message #{message.id} (attempt #{delivery_attempt.attempt_count}): #{error.message}"
      Waha::DeliverJob.set(wait: RETRY_DELAYS[delivery_attempt.attempt_count - 1]).perform_later(message.id)
    else
      fail_message!(error)
    end
  end

  # The request that carried our pre-generated id may have reached WAHA despite
  # the local error (timeout, reset, 5xx). Before assuming nothing happened and
  # resending, check whether that id already shows up as a message WAHA sent.
  # Only meaningful once a request was actually dispatched with a known id; a
  # failure before that point (e.g. fetching the id itself) has nothing to
  # reconcile against.
  def reconcile_ambiguous_dispatch!
    return false unless delivery_attempt.dispatched_at? && delivery_attempt.client_message_id.present?

    match = recent_own_messages.find { |msg| Waha::Anchoring.stanza_of(msg['id']) == delivery_attempt.client_message_id }
    return false unless match

    delivery_attempt.confirm_sent!(match['id'])
    true
  rescue StandardError => e
    Rails.logger.warn "[WAHA] Reconciliation check failed for message #{message.id}: #{e.message}"
    false
  end

  def recent_own_messages
    query = "limit=#{RECONCILIATION_LOOKBACK}&filter.fromMe=true&sortOrder=desc&downloadMedia=false"
    http_client.get_array("#{channel.session_name}/chats/#{chat_id}/messages?#{query}")
  end

  def fail_message!(error)
    return unless delivery_attempt.mark_failed!(error.message)

    Rails.logger.error "[WAHA] Send failed for message #{message.id}: #{error.message}"
    message.update!(status: :failed, external_error: error.message)
  end

  def delivery_attempt
    @delivery_attempt ||= WahaDeliveryAttempt.create_or_find_by!(message: message) do |a|
      a.channel = channel
      a.chat_jid = chat_id
    end
  end

  def reserve_and_queue_delivery
    humanized = humanization_enabled?
    duration_ms = humanized ? typing_duration_ms : 0
    queue_wait_ms, total_wait_ms = conversation_clock.reserve(duration_ms)
    if humanized && queue_wait_ms <= TYPING_PRESENCE_QUEUE_WAIT_LIMIT
      presence_client.public_send(audio_message? ? :recording : :typing, chat_id)
    end
    Waha::DeliverJob.set(wait: total_wait_ms / 1000.0).perform_later(message.id)
  rescue Redis::BaseError, ConnectionPool::TimeoutError => e
    warn_clock_unavailable(e)
    deliver_message
  end

  def typing_duration_ms
    (Waha::TypingSimulator.duration_for(message.content) * 1000).round
  end

  def pause_presence
    return unless clock_enabled?
    return if conversation_clock.backlog?

    presence_client.paused(chat_id)
  rescue Redis::BaseError, ConnectionPool::TimeoutError => e
    warn_clock_unavailable(e)
  end

  def warn_clock_unavailable(error)
    Rails.logger.warn "[WAHA] Conversation clock unavailable for message #{message.id}: #{error.message}"
  end

  def send_seen
    return if skip_presence || !channel.auto_read_receipts || presence_excluded?

    source_id = conversation.last_incoming_message&.source_id
    return if source_id.blank?

    presence_client.seen(chat_id, message_ids: [source_id])
  end

  def clock_enabled?
    channel.typing_simulation_enabled? && !presence_excluded?
  end

  def humanization_enabled?
    return false unless clock_enabled?

    text_message? || audio_message?
  end

  def presence_excluded?
    message.additional_attributes['campaign_id'].present? || Waha::Jid.group?(chat_id)
  end

  def text_message?
    attachment.blank? && message.content.present?
  end

  def audio_message?
    attachment&.file_type.to_s == 'audio'
  end

  def attachment
    @attachment ||= message.attachments.to_a.first
  end

  def conversation_clock
    @conversation_clock ||= Waha::ConversationClock.new(conversation_id: conversation.id)
  end

  def presence_client
    @presence_client ||= Waha::PresenceClient.new(channel: channel)
  end

  def send_text
    http_client.post('sendText', base_payload.merge(outgoing_mentions.payload, text: signer.sign(outgoing_mentions.text)))
  end

  def send_attachment
    file_url = attachment_url(attachment)
    return if file_url.blank?

    endpoint, body = attachment_endpoint_and_body(attachment.file_type.to_sym, attachment, file_url)
    http_client.post(endpoint, base_payload.merge(body))
  end

  def blob(attachment)
    attachment.file.blob
  end

  # WAHA's RemoteFile requires mimetype; sendFile also needs filename to preserve
  # the document name on WhatsApp. Passing them explicitly avoids the "422 file
  # invalid" the server returns for a bare `{ url: ... }`.
  def attachment_endpoint_and_body(file_type, attachment, file_url)
    caption = signer.sign(outgoing_mentions.text.presence)
    remote_file = { url: file_url, mimetype: blob(attachment)&.content_type.presence,
                    filename: blob(attachment)&.filename&.to_s.presence }.compact
    caption_payload = outgoing_mentions.payload.merge(file: remote_file, caption: caption)
    case file_type
    when :image  then ['sendImage', caption_payload]
    when :audio  then ['sendVoice', { file: remote_file }]
    when :video  then ['sendVideo', caption_payload]
    else              ['sendFile', caption_payload]
    end
  end

  def base_payload
    payload = {
      session: channel.session_name,
      chatId: chat_id
    }

    # The WAHA send API takes reply_to (snake_case); replyTo only appears in
    # incoming webhook payloads.
    reply_to_id = quoted_source_id
    payload[:reply_to] = reply_to_id if reply_to_id.present?
    payload[:id] = delivery_attempt.client_message_id if delivery_attempt.client_message_id.present?

    payload
  end

  # `outgoing_content` (not the raw `content`) so an input_csat message picks up
  # the survey link the same way every other non-web-widget channel's send
  # service already does — see MessageContentPresenter#outgoing_content.
  def outgoing_mentions
    @outgoing_mentions ||= Waha::OutgoingMentionParser.new(text: message.outgoing_content, chat_id: chat_id)
  end

  def chat_id
    contact_inbox.source_id
  end

  # WhatsApp keeps a single message across N edits, so when the agent replies to
  # an edit mirror the replyTo must be the family anchor (the original message's
  # source_id) — otherwise WhatsApp won't find the quoted message.
  def quoted_source_id
    external_id = message.content_attributes&.dig('in_reply_to_external_id')
    in_reply_to_id = message.content_attributes&.dig('in_reply_to')

    quoted = quoted_message(external_id, in_reply_to_id)
    return external_id if quoted.blank?

    Waha::Anchoring.anchor_source_id(quoted)
  end

  def quoted_message(external_id, in_reply_to_id)
    (inbox.messages.find_by(source_id: external_id) if external_id.present?) ||
      (inbox.messages.find_by(id: in_reply_to_id) if in_reply_to_id.present?)
  end

  def attachment_url(attachment)
    return unless attachment.file.attached?

    # `download_url` returns the pre-signed blob URL directly, without the 301
    # redirect that WAHA's downloader doesn't follow.
    attachment.download_url.presence
  rescue StandardError
    nil
  end

  def http_client
    @http_client ||= Waha::HttpClient.new(channel: channel)
  end

  def signer
    @signer ||= Waha::MessageSigner.new(message: message)
  end
end
# rubocop:enable Metrics/ClassLength
