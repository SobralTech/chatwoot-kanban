class Waha::ImportChatWorkerJob < ApplicationJob
  queue_as :low

  THROTTLE = 0.5

  # One member of a channel's bounded import pool. It claims pending chats one at
  # a time (atomically, so workers never collide) and imports each until the queue
  # is drained, then the worker that empties it finalizes the import.
  def perform(channel_id, window)
    @channel = Channel::Waha.find_by(id: channel_id)
    return unless @channel

    @window = window
    loop do
      row = WahaImportChat.claim_next(@channel.id)
      break unless row

      import_chat(row)
      sleep THROTTLE
    end
    finalize_if_last
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
