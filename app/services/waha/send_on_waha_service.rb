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

    endpoint, body = attachment_endpoint_and_body(attachment.file_type.to_sym, file_url)
    http_client.post(endpoint, base_payload.merge(body))
  end

  def attachment_endpoint_and_body(file_type, file_url)
    caption = message.content.to_s.presence
    case file_type
    when :image  then ['sendImage', { file: { url: file_url }, caption: caption }]
    when :audio  then ['sendVoice', { file: { url: file_url } }]
    when :video  then ['sendVideo', { file: { url: file_url }, caption: caption }]
    else              ['sendFile',  { file: { url: file_url }, caption: caption }]
    end
  end

  def base_payload
    payload = {
      session: channel.session_name,
      chatId: chat_id
    }

    reply_to_id = quoted_source_id
    payload[:replyTo] = reply_to_id if reply_to_id.present?

    payload
  end

  def chat_id
    conversation.contact_inbox.source_id
  end

  def quoted_source_id
    external_id = message.content_attributes&.dig('in_reply_to_external_id')
    return external_id if external_id.present?

    in_reply_to_id = message.content_attributes&.dig('in_reply_to')
    return unless in_reply_to_id

    inbox.messages.find_by(id: in_reply_to_id)&.source_id
  end

  def attachment_url(attachment)
    return unless attachment.file.attached?

    Rails.application.routes.url_helpers.url_for(attachment.file)
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
