# One row per chat in a WAHA history import: the per-item work queue and progress
# store (moved out of the channel's import_state jsonb so the hot path does O(1)
# single-row writes and a bounded worker pool can claim chats concurrently).
# == Schema Information
#
# Table name: waha_import_chats
#
#  id              :bigint           not null, primary key
#  cursor          :bigint
#  error           :string
#  imported_count  :integer          default(0), not null
#  status          :integer          default("pending"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  channel_waha_id :bigint           not null
#  chat_id         :string           not null
#
# Indexes
#
#  index_waha_import_chats_on_channel_waha_id              (channel_waha_id)
#  index_waha_import_chats_on_channel_waha_id_and_chat_id  (channel_waha_id,chat_id) UNIQUE
#  index_waha_import_chats_on_channel_waha_id_and_status   (channel_waha_id,status)
#
# Foreign Keys
#
#  fk_rails_...  (channel_waha_id => channel_waha.id)
#
class WahaImportChat < ApplicationRecord
  belongs_to :channel, class_name: 'Channel::Waha', foreign_key: :channel_waha_id, inverse_of: :import_chats

  enum :status, { pending: 0, importing: 1, done: 2, failed: 3 }

  # Atomically hands the next pending chat to one worker: the SKIP LOCKED subquery
  # lets concurrent workers grab different rows without blocking, and the lock is
  # held only for this single statement (not the whole chat import). Returns nil
  # when the queue is drained. `uncached` is required because find_by_sql caches
  # this UPDATE...RETURNING as if it were a SELECT, so the worker's repeated calls
  # would otherwise all get the first claimed row.
  def self.claim_next(channel_id)
    uncached do
      find_by_sql([<<~SQL.squish, statuses[:importing], channel_id, statuses[:pending]]).first
        UPDATE waha_import_chats SET status = ?, updated_at = now()
        WHERE id = (
          SELECT id FROM waha_import_chats
          WHERE channel_waha_id = ? AND status = ?
          ORDER BY id LIMIT 1 FOR UPDATE SKIP LOCKED
        )
        RETURNING *
      SQL
    end
  end
end
