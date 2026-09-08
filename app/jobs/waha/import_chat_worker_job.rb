class Waha::ImportChatWorkerJob < ApplicationJob
  queue_as :low

  # Pause between chats. Applied as an enqueue delay rather than a sleep so the
  # worker hands its Sidekiq thread back between chats instead of pinning it.
  THROTTLE = 0.5.seconds
  LEASE = ENV.fetch('WAHA_IMPORT_CHAT_LEASE_SECONDS', 300).to_i.seconds
  MAX_RETRIES = ENV.fetch('WAHA_IMPORT_CHAT_MAX_RETRIES', 5).to_i

  # One member of a channel's bounded import pool. It claims a single pending chat
  # (atomically, so workers never collide), imports it and hands off to a successor
  # job. Doing one chat per execution keeps a multi-hour import from holding a
  # Sidekiq thread — and its database connection — for its whole duration, which
  # would otherwise starve every other queue in the process.
  #
  # The pool size is preserved exactly: each execution enqueues at most one
  # successor, and the worker that finds the queue drained finalizes the import.
  def perform(channel_id, window, kind = nil, execution_id = nil, pass_id = nil)
    @channel = Channel::Waha.find_by(id: channel_id)
    return unless @channel

    set_context(window, kind, execution_id, pass_id)
    row = claim_next_chat
    return finalize_if_last if row.nil?

    wait = Waha::AccountLocale.with(@channel) { import_chat(row) }
    enqueue_successor(wait || THROTTLE)
  end

  private

  def set_context(window, kind, execution_id, pass_id)
    # Jobs enqueued before the import kind became an explicit argument still
    # inherit the running import's semantics when they are eventually consumed.
    @kind = kind || @channel.import_state['kind'] || 'initial'
    @execution_id = execution_id || @channel.import_state['execution_id']
    @pass_id = pass_id || @channel.ensure_import_pass_identity!(@execution_id)
    persisted_window = @channel.import_window
    @window = persisted_window.values.all?(&:present?) ? persisted_window : window
  end

  # Claim under the channel lock as well as the chat-row lock. A new execution
  # can therefore never transition to scheduled between this worker validating
  # its token and marking a row importing; the long-running fetch stays outside
  # the lock and the worker pool remains parallel.
  def claim_next_chat
    @channel.with_lock do
      next unless @channel.import_running_for?(@execution_id, @pass_id)

      WahaImportChat.claim_next(
        channel_id: @channel.id, execution_id: @execution_id, pass_id: @pass_id, lease_duration: LEASE
      )
    end
  end

  # Per-chat isolation: one bad/slow chat is logged and marked failed instead of
  # stalling the pool. The chat's own row tracks its imported count + cursor.
  def import_chat(row)
    Waha::ChatHistoryImporter.new(
      channel: @channel, chat_id: row.chat_id, window: @window, import_chat: row,
      kind: @kind, lease_token: row.lease_token, lease_duration: LEASE
    ).run
    row.finish!(row.lease_token)
    nil
  rescue CustomExceptions::Waha::StaleImportWorker
    nil
  rescue CustomExceptions::Waha::TransientError => e
    retry_chat(row, e)
  rescue StandardError => e
    Waha::Telemetry.emit(
      :import_chat_failed, channel: @channel, chat: row.chat_id, level: :error, kind: @kind,
                           execution_id: @execution_id, pass: row.pass_number, pass_id: @pass_id,
                           error: e.class.name, imported_messages: row.imported_count, outcome: :terminal
    )
    fail_owned_chat(row, e.message)
    nil
  end

  def retry_chat(row, error)
    attempt = row.attempts + 1
    wait = ((attempt**2) * 10).seconds
    outcome = row.retry!(row.lease_token, error: error.message, wait: wait, max_attempts: MAX_RETRIES)
    Waha::Telemetry.emit(
      :import_chat_failed, channel: @channel, chat: row.chat_id, level: outcome == :failed ? :error : :warn,
                           kind: @kind, execution_id: @execution_id, pass: row.pass_number, pass_id: @pass_id,
                           error: error.class.name, imported_messages: row.imported_count, outcome: outcome,
                           try: attempt, max_tries: MAX_RETRIES, next_attempt_at: (wait.from_now.utc.iso8601 if outcome == :pending)
    )
    outcome == :pending ? wait : nil
  end

  # The worker that drains the queue asks the channel state machine to finalize.
  # Its execution token prevents an old delayed worker from finishing a newer run.
  def finalize_if_last
    @channel.finalize_import_if_drained!(@execution_id, @pass_id)
  end

  def enqueue_successor(wait)
    self.class.set(wait: wait).perform_later(@channel.id, @window, @kind, @execution_id, @pass_id)
  end

  def fail_owned_chat(row, message)
    row.fail!(row.lease_token, message)
  rescue CustomExceptions::Waha::StaleImportWorker
    nil
  end
end
