class Waha::HistoryMediaJob < ApplicationJob
  queue_as :low

  # Shorter than the default so a batch of expired-media fetches (old WhatsApp
  # media is frequently gone) doesn't tie up a worker for minutes per message.
  FETCH_TIMEOUT = 30

  # Downloads media for a page's worth of already-written history messages and
  # attaches it, best-effort. Runs off the import's critical path so the text
  # history lands fast; idempotent (skips messages that already have an
  # attachment) so a retry is safe.
  def perform(channel_id, chat_id, message_ids)
    channel = Channel::Waha.find_by(id: channel_id)
    return if channel.nil?

    Message.where(id: message_ids).find_each do |message|
      next if message.attachments.any?

      attach_media(channel, chat_id, message)
    end
  end

  private

  def attach_media(channel, chat_id, message)
    payload = fetch_message(channel, chat_id, message.source_id)
    return if payload.blank?

    Waha::MediaAttacher.new(channel: channel, payload: payload, message: message).attach
    return if message.attachments.blank?

    message.imported = true
    message.save!
  rescue StandardError => e
    Rails.logger.error "[WAHA] History media: message #{message.id} failed: #{e.message}"
  end

  def fetch_message(channel, chat_id, source_id)
    path = "#{channel.session_name}/chats/#{CGI.escape(chat_id.to_s)}/messages/#{CGI.escape(source_id.to_s)}?downloadMedia=true"
    response = Waha::HttpClient.new(channel: channel).get(path, timeout: FETCH_TIMEOUT)
    response.is_a?(Hash) ? response : nil
  end
end
