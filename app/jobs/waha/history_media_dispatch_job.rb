class Waha::HistoryMediaDispatchJob < ApplicationJob
  queue_as :low

  # Initial-import media is deliberately held until textual convergence reaches
  # a terminal state. This dispatcher is idempotent: duplicate recovery runs may
  # enqueue the same message IDs, and HistoryMediaJob skips attachments already
  # present while retaining finite, observable retry behavior for the rest.
  def perform(channel_id, execution_id)
    channel = Channel::Waha.find_by(id: channel_id)
    return unless channel&.import_state&.slice('execution_id', 'media_pending') == {
      'execution_id' => execution_id, 'media_pending' => true
    }

    channel.import_chats.where.not(media_message_ids: []).find_each do |row|
      Waha::HistoryMediaJob.perform_later(channel.id, row.chat_id, row.media_message_ids)
    end
    channel.complete_media_dispatch!(execution_id)
  end
end
