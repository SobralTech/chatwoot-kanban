class Waha::HistoryImportJob < ApplicationJob
  queue_as :low

  MAX_RETRIES = 5
  # GOWS reports WORKING before its initial history sync has populated the chat store.
  INITIAL_DELAY = ENV.fetch('WAHA_INITIAL_IMPORT_DELAY_SECONDS', 120).to_i.seconds
  # Bounded per-channel parallelism: how many chats import at once. Tunable in
  # production without a deploy; kept well under Sidekiq concurrency so one
  # channel's import doesn't starve other work (or hammer the WAHA session).
  WORKER_POOL = ENV.fetch('WAHA_IMPORT_CONCURRENCY', 4).to_i

  # Dispatches a history import for one WAHA channel. Only the job carrying the
  # persisted scheduled execution token can transition it to running; duplicate
  # or stale jobs return before they can seed, reclaim, or dispatch chat workers.
  # The import kind travels with each worker so initial backfill and recent gap
  # recovery keep distinct message and conversation semantics.
  def perform(channel_id, window, kind, execution_id = nil)
    @channel = Channel::Waha.find_by(id: channel_id)
    return unless @channel

    @window = window
    @kind = kind
    @execution_id = @channel.start_scheduled_import!(execution_id)
    return unless @execution_id

    dispatch_chats
  rescue StandardError => e
    handle_failure(e)
  end

  private

  def dispatch_chats
    chat_ids = Waha::ChatOverviewFetcher.new(channel: @channel).all
    raise CustomExceptions::Waha::HistoryNotReady, 'WAHA chat history is not ready yet' if @kind == 'initial' && chat_ids.empty?

    seed_chat_rows(chat_ids)
    reclaim_stale_rows
    return @channel.finalize_import_if_drained!(@execution_id) unless @channel.import_chats.exists?

    # Never spin up more workers than there are chats for them to claim.
    pending_count = @channel.import_chats.pending.count
    return @channel.finalize_import_if_drained!(@execution_id) if pending_count.zero?

    pending_count.clamp(1, WORKER_POOL).times do
      Waha::ImportChatWorkerJob.perform_later(@channel.id, @window, @kind, @execution_id)
    end
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

  # A new dispatcher is only scheduled after no worker owns a row, so any
  # `importing` row here is from a previously interrupted dispatcher. The row's
  # cursor remains intact when it is re-claimed.
  def reclaim_stale_rows
    # rubocop:disable Rails/SkipsModelValidations
    @channel.import_chats.importing.update_all(status: WahaImportChat.statuses[:pending])
    # rubocop:enable Rails/SkipsModelValidations
  end

  # Only systemic failures (e.g. the chat-overview fetch) reach here — per-chat
  # failures are isolated inside the workers.
  def handle_failure(error)
    return if @channel.nil?

    outcome = @channel.retry_import_after_failure!(@execution_id, error.message)
    return unless outcome

    case outcome[:status]
    when :scheduled
      Rails.logger.warn "[WAHA] History import: channel #{@channel.id} retry #{outcome[:retries]}/#{MAX_RETRIES}: #{error.message}"
    when :failed
      Rails.logger.error "[WAHA] History import: channel #{@channel.id} failed after #{MAX_RETRIES} retries: #{error.message}"
    when :running
      Rails.logger.warn "[WAHA] History import: channel #{@channel.id} dispatcher failed while workers remain active: #{error.message}"
    end
  end
end
