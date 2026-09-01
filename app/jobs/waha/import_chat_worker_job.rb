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
  def perform(channel_id, window)
    @channel = Channel::Waha.find_by(id: channel_id)
    return unless @channel

    @window = window
    row = WahaImportChat.claim_next(@channel.id)
    return finalize_if_last if row.nil?

    import_chat(row)
    self.class.set(wait: THROTTLE).perform_later(@channel.id, @window)
  end

  private

  # Per-chat isolation: one bad/slow chat is logged and marked failed instead of
  # stalling the pool. The chat's own row tracks its imported count + cursor.
  def import_chat(row)
    Waha::ChatHistoryImporter.new(channel: @channel, chat_id: row.chat_id, window: @window, import_chat: row).run
    row.done!
  rescue StandardError => e
    Rails.logger.error "[WAHA] History import: chat #{row.chat_id} failed: #{e.message}"
    row.update!(status: :failed, error: e.message.to_s.truncate(500))
  end

  # The worker that drains the queue finalizes the import. A row lock serializes
  # the check so concurrent workers can't double-finalize, and a chat still
  # importing in another worker defers finalization to that worker.
  def finalize_if_last
    @channel.with_lock do
      next unless @channel.import_state['status'] == 'running'
      next if @channel.import_chats.exists?(status: %i[pending importing])

      @channel.finalize_import!
    end
  end
end
