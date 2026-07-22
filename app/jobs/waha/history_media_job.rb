class Waha::HistoryMediaJob < ApplicationJob
  queue_as :low

  # Shorter than the default so a batch of expired-media fetches (old WhatsApp
  # media is frequently gone) doesn't tie up a worker for minutes per message.
  FETCH_TIMEOUT = 30
  # Small pause between fetches so a chat's media trickles out instead of pounding
  # the (shared) WAHA session back to back.
  THROTTLE = 0.5
  # Stop the batch after this many consecutive failures: a struggling WAHA session
  # shouldn't keep getting hammered — it protects the shared host and avoids
  # WhatsApp throttling the number. Remaining media stays best-effort (unattached).
  MAX_CONSECUTIVE_FAILURES = 5

  # Downloads media for one chat's already-written history messages and attaches
  # it, best-effort. Runs off the import's critical path (text lands fast) and
  # serially (one job per chat); idempotent — skips messages that already have an
  # attachment, so a retry is safe.
  def perform(channel_id, chat_id, message_ids)
    channel = Channel::Waha.find_by(id: channel_id)
    return if channel.nil?

    consecutive_failures = 0
    Message.where(id: message_ids).find_each do |message|
      next if message.attachments.any?

      if attach_media(channel, chat_id, message)
        consecutive_failures = 0
      else
        consecutive_failures += 1
        break if consecutive_failures >= MAX_CONSECUTIVE_FAILURES
      end
      sleep THROTTLE
    end
  end

  private

  # Returns true only when media was fetched and attached; false on any miss or
  # error so the caller can trip the circuit breaker.
  def attach_media(channel, chat_id, message)
    payload = fetch_message(channel, chat_id, message.source_id)
    return false if payload.blank?

    Waha::MediaAttacher.new(channel: channel, payload: payload, message: message).attach
    return false if message.attachments.blank?

    message.imported = true
    message.save!
    true
  rescue StandardError => e
    Rails.logger.error "[WAHA] History media: message #{message.id} failed: #{e.message}"
    false
  end

  def fetch_message(channel, chat_id, source_id)
    path = "#{channel.session_name}/chats/#{CGI.escape(chat_id.to_s)}/messages/#{CGI.escape(source_id.to_s)}?downloadMedia=true"
    response = Waha::HttpClient.new(channel: channel).get(path, timeout: FETCH_TIMEOUT)
    response.is_a?(Hash) ? response : nil
  end
end
