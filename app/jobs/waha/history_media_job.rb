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
    @channel = Channel::Waha.find_by(id: channel_id)
    @chat_id = chat_id
    return if @channel.nil?

    remaining = Array(message_ids)
    return if remaining.first.nil?

    outcome = Waha::AccountLocale.with(@channel) { process(remaining.first) }
    remaining.shift unless outcome == :transient
    return if remaining.empty?

    chain(remaining, outcome == :success ? 0 : consecutive_failures + 1)
  end

  private

  # Hands the rest of the chat's media to a successor job, pausing longer once
  # the circuit breaker trips — which is itself a signal, since a chat whose
  # media is repeatedly failing is a backlog that will not drain on its own.
  def chain(remaining, failures)
    tripped = failures >= MAX_CONSECUTIVE_FAILURES
    if tripped
      observe(nil, signal: :media_backlog_paused, level: :warn, reason: :consecutive_failures,
                   pending: remaining.size, delay_ms: FAILURE_COOLDOWN.in_milliseconds)
    end
    wait, next_failures = tripped ? [FAILURE_COOLDOWN, 0] : [THROTTLE, failures]
    self.class.set(wait: wait).perform_later(@channel.id, @chat_id, remaining, next_failures)
  end

  # A message that already carries an attachment was done by an earlier run; it
  # succeeds without counting against the circuit breaker.
  def process(message_id)
    message = @channel.inbox.messages.find_by(id: message_id)
    return :success if message.nil?
    return finalize(message, terminal: false) if message.attachments.exists?

    attach_media(message)
  end

  # :success - media fetched and attached. :transient - worth retrying (network
  # blip, WAHA 5xx/timeout); trips the circuit breaker but keeps the item queued.
  # :terminal - registered as a permanent failure (Waha::MediaAttacher's visible
  # fallback) and the item is skipped for good.
  def attach_media(message)
    mapping = Waha::Anchoring.mappings_for(message).first
    return finalize(message, terminal: true, reason: :missing_mapping) unless mapping

    payload = fetch_message(mapping.chat_jid, mapping.provider_id)
    return finalize(message, terminal: true, reason: :message_gone) if payload.blank?

    Waha::MediaAttacher.new(channel: @channel, payload: payload).attach_to(message)
    finalize(message, terminal: message.attachments.blank?, reason: :not_attached)
  rescue CustomExceptions::Waha::TransientError => e
    observe(message, level: :warn, outcome: :transient, reason: :fetch_failed, error: e.class.name)
    :transient
  rescue StandardError => e
    observe(message, level: :error, outcome: :terminal, reason: :fetch_failed, error: e.class.name)
    finalize(message, terminal: true)
  end

  def finalize(message, terminal:, reason: nil)
    if terminal
      Waha::MediaAttacher.mark_download_failed(message)
    else
      Waha::MediaAttacher.mark_download_succeeded(message)
    end
    message.imported = true
    message.save!
    return :success unless terminal

    observe(message, level: :info, outcome: :terminal, reason: reason) if reason
    :terminal
  end

  def observe(message, signal: :media_download, **context)
    Waha::Telemetry.emit(signal, channel: @channel, chat: @chat_id, scope: :history, message_id: message&.id, **context)
  end

  def fetch_message(chat_jid, source_id)
    path = "#{@channel.session_name}/chats/#{CGI.escape(chat_jid.to_s)}/messages/#{CGI.escape(source_id.to_s)}?downloadMedia=true"
    response = http_client.get(path, timeout: FETCH_TIMEOUT)
    response.is_a?(Hash) ? response : nil
  end

  def http_client
    @http_client ||= Waha::HttpClient.new(channel: @channel)
  end
end
