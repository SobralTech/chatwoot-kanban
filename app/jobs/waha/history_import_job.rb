class Waha::HistoryImportJob < ApplicationJob
  queue_as :low

  MAX_RETRIES = 5
  INITIAL_DELAY = ENV.fetch('WAHA_INITIAL_IMPORT_DELAY_SECONDS', 120).to_i.seconds
  WORKER_POOL = ENV.fetch('WAHA_IMPORT_CONCURRENCY', 4).to_i
  PASS_INTERVAL = ENV.fetch('WAHA_IMPORT_PASS_INTERVAL_SECONDS', 30).to_i.seconds
  QUIET_PERIOD = ENV.fetch('WAHA_IMPORT_QUIET_PERIOD_SECONDS', 120).to_i.seconds
  MAX_PASSES = ENV.fetch('WAHA_IMPORT_MAX_PASSES', 10).to_i
  MAX_SETTLING_TIME = ENV.fetch('WAHA_IMPORT_MAX_SETTLING_SECONDS', 1800).to_i.seconds
  DISPATCHER_LEASE = ENV.fetch('WAHA_IMPORT_DISPATCHER_LEASE_SECONDS', 120).to_i.seconds

  # One invocation dispatches one complete pass over the execution's fixed
  # window. The persisted execution/pass pair is the authority: old delayed jobs
  # and duplicate deliveries cannot discover chats or enqueue workers.
  def perform(channel_id, window, kind, execution_id = nil, pass_id = nil)
    @channel = Channel::Waha.find_by(id: channel_id)
    return unless @channel

    @kind = kind
    @execution_id = execution_id || @channel.import_state['execution_id']
    @pass_id = pass_id || @channel.ensure_import_pass_identity!(@execution_id)
    @window = persisted_window_or(window)
    @dispatcher_token = @channel.claim_import_pass!(@execution_id, @pass_id)
    return unless @dispatcher_token

    dispatch_pass
  rescue StandardError => e
    handle_failure(e)
  end

  private

  def persisted_window_or(fallback)
    persisted = @channel.import_window
    persisted.values.all?(&:present?) ? persisted : fallback
  end

  def dispatch_pass
    chat_ids = Waha::ChatOverviewFetcher.new(channel: @channel).all.uniq
    seed_chat_rows(chat_ids)
    rows = @channel.import_chats.for_pass(@execution_id, @pass_id)
    new_chats = rows.where(discovered_pass: @channel.import_state['pass_number']).count
    return unless @channel.begin_import_pass!(@execution_id, @pass_id, @dispatcher_token, new_chats: new_chats)

    return @channel.finalize_import_if_drained!(@execution_id, @pass_id) unless rows.exists?

    pending_count = rows.claimable.count
    return @channel.finalize_import_if_drained!(@execution_id, @pass_id) if pending_count.zero?

    Waha::Telemetry.emit(
      :import_pass_started, channel: @channel, level: :info, kind: @kind, execution_id: @execution_id,
                            pass: @channel.import_state['pass_number'], pass_id: @pass_id,
                            chats: rows.count, new_chats: new_chats, pending: pending_count
    )
    enqueue_workers(pending_count)
  end

  def seed_chat_rows(chat_ids)
    return if chat_ids.blank?

    now = Time.current
    pass_number = @channel.import_state['pass_number']
    rows = chat_ids.map do |chat_id|
      {
        channel_waha_id: @channel.id, chat_id: chat_id, execution_id: @execution_id,
        pass_id: @pass_id, pass_number: pass_number, discovered_pass: pass_number,
        created_at: now, updated_at: now
      }
    end
    # rubocop:disable Rails/SkipsModelValidations
    WahaImportChat.insert_all(rows, unique_by: %i[channel_waha_id chat_id])
    # rubocop:enable Rails/SkipsModelValidations
  end

  def enqueue_workers(pending_count)
    pending_count.clamp(1, WORKER_POOL).times do
      Waha::ImportChatWorkerJob.perform_later(@channel.id, @window, @kind, @execution_id, @pass_id)
    end
  end

  def handle_failure(error)
    return if @channel.nil? || @dispatcher_token.nil?

    outcome = transient?(error) ? @channel.retry_import_dispatch!(@execution_id, @pass_id, @dispatcher_token, error) : fail_terminal(error)
    observe_failure(error, outcome)
  end

  def transient?(error)
    error.is_a?(CustomExceptions::Waha::TransientError)
  end

  def fail_terminal(error)
    @channel.fail_import_dispatch!(@execution_id, @pass_id, @dispatcher_token, error)
  end

  def observe_failure(error, outcome)
    return unless outcome

    Waha::Telemetry.emit(
      :import_dispatch_failed, channel: @channel, level: outcome[:status] == :failed ? :error : :warn,
                               kind: @kind, execution_id: @execution_id, pass: @channel.import_state['pass_number'],
                               pass_id: @pass_id, outcome: outcome[:status], error: error.class.name,
                               try: outcome[:retries], max_tries: MAX_RETRIES
    )
  end
end
