# One row per chat in a WAHA history import: the per-item work queue and progress
# store (moved out of the channel's import_state jsonb so the hot path does O(1)
# single-row writes and a bounded worker pool can claim chats concurrently).
# == Schema Information
#
# Table name: waha_import_chats
#
#  id                           :bigint           not null, primary key
#  attempts                     :integer          default(0), not null
#  cursor                       :bigint
#  discovered_pass              :integer          default(1), not null
#  error                        :string
#  imported_count               :integer          default(0), not null
#  lease_expires_at             :datetime
#  lease_token                  :string
#  media_message_ids            :bigint           default([]), not null, is an Array
#  next_attempt_at              :datetime
#  observed_message_count       :integer          default(0), not null
#  observed_message_digest      :string
#  pass_imported_count          :integer          default(0), not null
#  pass_number                  :integer          default(1), not null
#  pass_observed_message_count  :integer          default(0), not null
#  pass_observed_message_digest :string
#  status                       :integer          default("pending"), not null
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  channel_waha_id              :bigint           not null
#  chat_id                      :string           not null
#  cursor_message_id            :string
#  execution_id                 :string
#  pass_id                      :string
#
# Indexes
#
#  index_waha_import_chats_on_channel_waha_id              (channel_waha_id)
#  index_waha_import_chats_on_channel_waha_id_and_chat_id  (channel_waha_id,chat_id) UNIQUE
#  index_waha_import_chats_on_channel_waha_id_and_status   (channel_waha_id,status)
#  index_waha_import_chats_on_lease_expires_at             (lease_expires_at)
#  index_waha_import_chats_on_pass_claim                   (channel_waha_id,execution_id,pass_id,status)
#
# Foreign Keys
#
#  fk_rails_...  (channel_waha_id => channel_waha.id)
#
class WahaImportChat < ApplicationRecord
  belongs_to :channel, class_name: 'Channel::Waha', foreign_key: :channel_waha_id, inverse_of: :import_chats

  enum :status, { pending: 0, importing: 1, done: 2, failed: 3 }

  scope :for_pass, ->(execution_id, pass_id) { where(execution_id: execution_id, pass_id: pass_id) }
  scope :claimable, -> { pending.where('next_attempt_at IS NULL OR next_attempt_at <= ?', Time.current) }

  def self.claim_next(channel_id:, execution_id:, pass_id:, lease_duration:)
    uncached do
      transaction do
        row = for_pass(execution_id, pass_id).claimable.where(channel_waha_id: channel_id).order(:id).lock('FOR UPDATE SKIP LOCKED').first
        next unless row

        row.update!(
          status: :importing,
          lease_token: SecureRandom.uuid,
          lease_expires_at: lease_duration.from_now,
          next_attempt_at: nil
        )
        row
      end
    end
  end

  def self.reclaim_expired!(channel_id:, execution_id:, pass_id:, max_attempts:, legacy_stale_before:)
    counts = { reclaimed: 0, failed: 0 }
    stale = for_pass(execution_id, pass_id).where(channel_waha_id: channel_id).importing.where(
      'lease_expires_at <= :now OR (lease_expires_at IS NULL AND updated_at <= :legacy_stale_before)',
      now: Time.current, legacy_stale_before: legacy_stale_before
    )
    stale.find_each do |row|
      outcome = reclaim_expired_row(row, max_attempts, legacy_stale_before)
      counts[outcome] += 1 if outcome
    end
    counts
  end

  def self.lease_expired?(row, legacy_stale_before)
    row.lease_expires_at ? row.lease_expires_at <= Time.current : row.updated_at <= legacy_stale_before
  end

  def self.reclaim_expired_row(row, max_attempts, legacy_stale_before)
    row.with_lock do
      next unless row.importing? && lease_expired?(row, legacy_stale_before)

      attempts = row.attempts + 1
      if attempts <= max_attempts
        wait = ((attempts**2) * 10).seconds
        row.update!(status: :pending, attempts: attempts, next_attempt_at: wait.from_now,
                    lease_token: nil, lease_expires_at: nil, error: 'Worker lease expired')
        :reclaimed
      else
        row.update!(status: :failed, attempts: attempts, next_attempt_at: nil,
                    lease_token: nil, lease_expires_at: nil, error: 'Worker lease expired repeatedly')
        :failed
      end
    end
  end
  private_class_method :lease_expired?, :reclaim_expired_row

  def heartbeat!(token, lease_duration:)
    update_owned!(token, lease_expires_at: lease_duration.from_now)
  end

  def checkpoint!(token, attrs)
    update_owned!(token, attrs)
  end

  def finish!(token)
    update_owned!(token, status: :done, lease_token: nil, lease_expires_at: nil, next_attempt_at: nil, error: nil)
  end

  def retry!(token, error:, wait:, max_attempts:)
    next_attempt = attempts + 1
    attrs = { attempts: next_attempt, error: error.to_s.truncate(500), lease_token: nil, lease_expires_at: nil }
    if next_attempt <= max_attempts
      update_owned!(token, attrs.merge(status: :pending, next_attempt_at: wait.from_now))
      :pending
    else
      update_owned!(token, attrs.merge(status: :failed, next_attempt_at: nil))
      :failed
    end
  end

  def fail!(token, error)
    update_owned!(token, status: :failed, error: error.to_s.truncate(500), lease_token: nil, lease_expires_at: nil, next_attempt_at: nil)
  end

  private

  def update_owned!(token, attrs)
    relation = self.class.where(id: id, status: self.class.statuses[:importing], lease_token: token)
    relation = relation.where('lease_expires_at > ?', Time.current)
    # rubocop:disable Rails/SkipsModelValidations
    raise CustomExceptions::Waha::StaleImportWorker unless relation.update_all(attrs.merge(updated_at: Time.current)) == 1
    # rubocop:enable Rails/SkipsModelValidations

    assign_attributes(attrs)
  end
end
