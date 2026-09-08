class Waha::ImportChatWorkerJob < ApplicationJob
  queue_as :low

  # Pause between chats. Applied as an enqueue delay rather than a sleep so the
  # worker hands its Sidekiq thread back between chats instead of pinning it.
  THROTTLE = 0.5.seconds

  # One member of a channel's bounded import pool. It claims a single pending chat
  # (atomically, so workers never collide), imports it and hands off to a successor
  # job. Doing one chat per execution keeps a multi-hour import from holding a
  # Sidekiq thread — and its database connection — for its whole duration, which
  # would otherwise starve every other queue in the process.
  #
  # The pool size is preserved exactly: each execution enqueues at most one
  # successor, and the worker that finds the queue drained finalizes the import.
  def perform(channel_id, window, kind = nil, execution_id = nil)
    @channel = Channel::Waha.find_by(id: channel_id)
    return unless @channel

    @window = window
    # Jobs enqueued before the import kind became an explicit argument still
    # inherit the running import's semantics when they are eventually consumed.
    @kind = kind || @channel.import_state['kind'] || 'initial'
    @execution_id = execution_id
    row = claim_next_chat
    return finalize_if_last if row.nil?

    import_chat(row)
    self.class.set(wait: THROTTLE).perform_later(@channel.id, @window, @kind, @execution_id)
  end

  private

  # Claim under the channel lock as well as the chat-row lock. A new execution
  # can therefore never transition to scheduled between this worker validating
  # its token and marking a row importing; the long-running fetch stays outside
  # the lock and the worker pool remains parallel.
  def claim_next_chat
    @channel.with_lock do
      next unless @channel.import_running_for?(@execution_id)

      WahaImportChat.claim_next(@channel.id)
    end
  end

  # Per-chat isolation: one bad/slow chat is logged and marked failed instead of
  # stalling the pool. The chat's own row tracks its imported count + cursor.
  def import_chat(row)
    Waha::ChatHistoryImporter.new(channel: @channel, chat_id: row.chat_id, window: @window, import_chat: row, kind: @kind).run
    row.done!
  rescue StandardError => e
    Waha::Telemetry.emit(
      :import_chat_failed, channel: @channel, chat: row.chat_id, level: :error, kind: @kind,
                           execution_id: @execution_id, error: e.class.name, imported_messages: row.imported_count
    )
    row.update!(status: :failed, error: e.message.to_s.truncate(500))
  end

  # The worker that drains the queue asks the channel state machine to finalize.
  # Its execution token prevents an old delayed worker from finishing a newer run.
  def finalize_if_last
    @channel.finalize_import_if_drained!(@execution_id)
  end
end
