class Waha::HistoryMediaJob < ApplicationJob
  queue_as :low

  # Shorter than the default so a batch of expired-media fetches (old WhatsApp
  # media is frequently gone) doesn't tie up a worker for minutes per message.
  FETCH_TIMEOUT = 30
  # Small pause between fetches so a chat's media trickles out instead of pounding
  # the (shared) WAHA session back to back. Applied as an enqueue delay rather than
  # a sleep so the worker thread is not pinned while it waits.
  THROTTLE = 0.5.seconds
  # Five consecutive misses trigger a longer pause to protect a struggling WAHA
  # session. The remaining media is resumed afterwards instead of being dropped.
  MAX_CONSECUTIVE_FAILURES = 5
  FAILURE_COOLDOWN = 1.minute

  # Downloads media for one chat's already-written history messages and attaches
  # it, best-effort. Runs off the import's critical path (text lands fast) and
  # serially (one job per chat); idempotent — skips messages that already have an
  # attachment, so a retry is safe.
  #
  # One message per execution: a chat's media fetches are each capped at
  # FETCH_TIMEOUT, but a chat with hundreds of them would otherwise hold a single
  # Sidekiq thread (and its database connection) for over an hour, and an import
  # enqueues one of these per chat. Chaining keeps the same serial, throttled
  # behaviour while bounding a thread to a single fetch.
  def perform(channel_id, chat_id, message_ids, consecutive_failures = 0)
    channel = Channel::Waha.find_by(id: channel_id)
    return if channel.nil?

    remaining = Array(message_ids)
    message_id = remaining.shift
    return if message_id.nil?

    failures = process(channel, chat_id, message_id, consecutive_failures)
    return if remaining.empty?

    wait, next_failures = failures >= MAX_CONSECUTIVE_FAILURES ? [FAILURE_COOLDOWN, 0] : [THROTTLE, failures]
    self.class.set(wait: wait).perform_later(channel_id, chat_id, remaining, next_failures)
  end

  private

  # A message that already carries an attachment was done by an earlier run; it is
  # skipped without counting against the circuit breaker.
  def process(channel, chat_id, message_id, consecutive_failures)
    message = Message.where(id: message_id).where.missing(:attachments).first
    return consecutive_failures if message.nil?

    attach_media(channel, chat_id, message) ? 0 : consecutive_failures + 1
  end

  # Returns true only when media was fetched and attached; false on any miss or
  # error so the caller can trip the circuit breaker.
  def attach_media(channel, chat_id, message)
    payload = fetch_message(channel, chat_id, message.source_id)
    return false if payload.blank?

    Waha::MediaAttacher.new(channel: channel, payload: payload).attach_to(message)
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
    response = http_client(channel).get(path, timeout: FETCH_TIMEOUT)
    response.is_a?(Hash) ? response : nil
  end

  def http_client(channel)
    @http_client ||= Waha::HttpClient.new(channel: channel)
  end
end
