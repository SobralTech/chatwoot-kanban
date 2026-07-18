class Waha::SendOnWahaService < Base::SendOnChannelService
  private

  def channel_class
    Channel::Waha
  end

  def perform_reply
    result = send_message_to_waha
    message.update!(source_id: result['id']) if result&.dig('id').present?
  rescue StandardError => e
    Rails.logger.error "[WAHA] Send failed for message #{message.id}: #{e.message}"
    message.update!(status: :failed, external_error: e.message)
  end

  def send_message_to_waha
    case message.content_type.to_s
    when 'input_csat'
      nil
    else
      if message.attachments.any?
        send_attachment
      else
        send_text
      end
    end
  end

  def send_text
    http_client.post('sendText', base_payload.merge(text: message.content.to_s))
  end

  def send_attachment
    attachment = message.attachments.first
    file_url = attachment_url(attachment)
    return if file_url.blank?

    endpoint, body = attachment_endpoint_and_body(attachment.file_type.to_sym, attachment, file_url)
    http_client.post(endpoint, base_payload.merge(body))
  end

  # WAHA's RemoteFile requires mimetype; sendFile also needs filename to preserve
  # the document name on WhatsApp. Passing them explicitly avoids the "422 file
  # invalid" the server returns for a bare `{ url: ... }`.
  def attachment_endpoint_and_body(file_type, attachment, file_url)
    caption = message.content.to_s.presence
    remote_file = { url: file_url, mimetype: attachment_mimetype(attachment), filename: attachment_filename(attachment) }.compact
    case file_type
    when :image  then ['sendImage', { file: remote_file, caption: caption }]
    when :audio  then ['sendVoice', { file: remote_file }]
    when :video  then ['sendVideo', { file: remote_file, caption: caption }]
    else              ['sendFile',  { file: remote_file, caption: caption }]
    end
  end

  def attachment_mimetype(attachment)
    attachment.file.blob&.content_type.presence
  end

  def attachment_filename(attachment)
    attachment.file.blob&.filename&.to_s.presence
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
    conversation.contact_inbox.source_id
  end

  # WhatsApp keeps a single message across N edits, so when the agent replies to
  # an edit mirror the replyTo must be the family anchor (the original message's
  # source_id) — otherwise WhatsApp won't find the quoted message.
  def quoted_source_id
    external_id = message.content_attributes&.dig('in_reply_to_external_id')
    in_reply_to_id = message.content_attributes&.dig('in_reply_to')

    quoted = quoted_message(external_id, in_reply_to_id)
    return external_id if quoted.blank?

    quoted.additional_attributes['edit_of'].presence || quoted.source_id
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

  def inbox
    conversation.inbox
  end
end
