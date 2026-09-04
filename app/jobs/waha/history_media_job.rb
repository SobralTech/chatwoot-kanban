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
  #
  # The current item only leaves the queue on :success or :terminal — a
  # :transient failure (network blip, WAHA 5xx) leaves it at the front so the
  # next run (after the throttle, or the circuit-breaker cooldown) retries the
  # very item that failed instead of skipping past it.
  def perform(channel_id, chat_id, message_ids, consecutive_failures = 0)
    channel = Channel::Waha.find_by(id: channel_id)
    return if channel.nil?

    remaining = Array(message_ids)
    message_id = remaining.first
    return if message_id.nil?

    outcome = process(channel, chat_id, message_id)
    remaining.shift unless outcome == :transient
    return if remaining.empty?

    failures = outcome == :success ? 0 : consecutive_failures + 1
    wait, next_failures = failures >= MAX_CONSECUTIVE_FAILURES ? [FAILURE_COOLDOWN, 0] : [THROTTLE, failures]
    self.class.set(wait: wait).perform_later(channel_id, chat_id, remaining, next_failures)
  end

  private

  # A message that already carries an attachment was done by an earlier run; it
  # succeeds without counting against the circuit breaker.
  def process(channel, chat_id, message_id)
    message = Message.where(id: message_id).where.missing(:attachments).first
    return :success if message.nil?

    attach_media(channel, chat_id, message)
  end

  # :success - media fetched and attached. :transient - worth retrying (network
  # blip, WAHA 5xx/timeout); trips the circuit breaker but keeps the item queued.
  # :terminal - registered as a permanent failure (Waha::MediaAttacher's visible
  # fallback) and the item is skipped for good.
  def attach_media(channel, chat_id, message)
    payload = fetch_message(channel, chat_id, message.source_id)
    return finalize(message, terminal: true) if payload.blank?

    Waha::MediaAttacher.new(channel: channel, payload: payload).attach_to(message)
    finalize(message, terminal: message.attachments.blank?)
  rescue CustomExceptions::Waha::TransientError => e
    Rails.logger.warn "[WAHA] History media: message #{message.id} transient failure: #{e.message}"
    :transient
  rescue StandardError => e
    Rails.logger.error "[WAHA] History media: message #{message.id} failed: #{e.message}"
    finalize(message, terminal: true)
  end

  def finalize(message, terminal:)
    Waha::MediaAttacher.mark_download_failed(message) if terminal
    message.imported = true
    message.save!
    terminal ? :terminal : :success
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
