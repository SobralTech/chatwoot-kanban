class Waha::SendOnWahaService < Base::SendOnChannelService
  TYPING_PRESENCE_QUEUE_WAIT_LIMIT = 20_000

  pattr_initialize [:message!, :skip_presence]

  private

  def channel_class
    Channel::Waha
  end

  def perform_reply
    # CSAT surveys have no WhatsApp representation.
    return if message.content_type.to_s == 'input_csat'

    send_seen

    if skip_presence
      pause_presence
      deliver_message
    elsif clock_enabled?
      reserve_and_queue_delivery
    else
      deliver_message
    end
  rescue StandardError => e
    Rails.logger.error "[WAHA] Send failed for message #{message.id}: #{e.message}"
    message.update!(status: :failed, external_error: e.message)
  end

  def deliver_message
    result = attachment ? send_attachment : send_text
    message.update!(source_id: result['id']) if result&.dig('id').present?
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
    http_client.post('sendText', base_payload.merge(text: signer.sign(message.content.to_s)))
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
    caption = signer.sign(message.content.to_s.presence)
    remote_file = { url: file_url, mimetype: blob(attachment)&.content_type.presence,
                    filename: blob(attachment)&.filename&.to_s.presence }.compact
    case file_type
    when :image  then ['sendImage', { file: remote_file, caption: caption }]
    when :audio  then ['sendVoice', { file: remote_file }]
    when :video  then ['sendVideo', { file: remote_file, caption: caption }]
    else              ['sendFile',  { file: remote_file, caption: caption }]
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

    payload
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
