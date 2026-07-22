class Waha::HistoryImportJob < ApplicationJob
  queue_as :low

  MAX_RETRIES = 5
  # Bounded per-channel parallelism: how many chats import at once. Tunable in
  # production without a deploy; kept well under Sidekiq concurrency so one
  # channel's import doesn't starve other work (or hammer the WAHA session).
  WORKER_POOL = ENV.fetch('WAHA_IMPORT_CONCURRENCY', 4).to_i

  # Dispatches a silent history import for one WAHA channel: it acquires the lock
  # (import_state.status == running), seeds the per-chat work queue, and spins up
  # a bounded worker pool that imports chats concurrently. Progress lives on the
  # per-chat rows, so a restart or retry just re-runs this and the pool resumes.
  def perform(channel_id, window, kind)
    @channel = Channel::Waha.find_by(id: channel_id)
    return unless @channel

    @window = window
    @kind = kind
    @channel.start_import!(kind: kind, window: window) unless resuming?
    dispatch_chats
  rescue StandardError => e
    handle_failure(e)
  end

  private

  # A retry/restart re-enqueues this job while status is still running; that run
  # resumes (keeps the existing chat rows) instead of wiping and restarting.
  def resuming?
    state = @channel.import_state
    state['status'] == 'running' && state['kind'] == @kind &&
      state['window_start'] == @window['window_start'] && state['window_end'] == @window['window_end']
  end

  def dispatch_chats
    chat_ids = Waha::ChatOverviewFetcher.new(channel: @channel).all
    seed_chat_rows(chat_ids)
    reclaim_stale_rows
    return @channel.finalize_import! unless @channel.import_chats.exists?

    WORKER_POOL.times { Waha::ImportChatWorkerJob.perform_later(@channel.id, @window) }
  end

  # Idempotent seed: ON CONFLICT DO NOTHING keeps the progress of chats already
  # queued by a prior run, so a resume only adds newly discovered chats.
  def seed_chat_rows(chat_ids)
    return if chat_ids.blank?

    now = Time.current
    rows = chat_ids.map { |chat_id| { channel_waha_id: @channel.id, chat_id: chat_id, created_at: now, updated_at: now } }
    # rubocop:disable Rails/SkipsModelValidations
    WahaImportChat.insert_all(rows, unique_by: %i[channel_waha_id chat_id])
    # rubocop:enable Rails/SkipsModelValidations
  end

  # A worker that died leaves its chat stuck in `importing`; requeue those so the
  # fresh pool re-claims them (the row's cursor resumes mid-chat).
  def reclaim_stale_rows
    # rubocop:disable Rails/SkipsModelValidations
    @channel.import_chats.importing.update_all(status: WahaImportChat.statuses[:pending])
    # rubocop:enable Rails/SkipsModelValidations
  end

  # Only systemic failures (e.g. the chat-overview fetch) reach here — per-chat
  # failures are isolated inside the workers.
  def handle_failure(error)
    channel = Channel::Waha.find_by(id: @channel&.id)
    return if channel.nil?

    channel.record_import_retry!
    if channel.import_retries <= MAX_RETRIES
      self.class.set(wait: backoff(channel)).perform_later(channel.id, @window, @kind)
    else
      channel.fail_import!(error.message)
    end
  end

  # Quadratic backoff: 10s, 40s, 90s, 160s, 250s.
  def backoff(channel)
    ((channel.import_retries**2) * 10).seconds
  end
end
