# == Schema Information
#
# Table name: waha_message_mappings
#
#  id              :bigint           not null, primary key
#  chat_jid        :string           not null
#  direction       :integer          not null
#  event_type      :integer          default("message"), not null
#  part            :integer          default(0), not null
#  participant_jid :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  channel_waha_id :bigint           not null
#  external_id     :string           not null
#  message_id      :bigint           not null
#
# Indexes
#
#  index_waha_message_mappings_on_channel_waha_id  (channel_waha_id)
#  index_waha_message_mappings_on_identity         (channel_waha_id,chat_jid,external_id,event_type) UNIQUE
#  index_waha_message_mappings_on_message_id       (message_id)
#
# Foreign Keys
#
#  fk_rails_...  (channel_waha_id => channel_waha.id)
#  fk_rails_...  (message_id => messages.id)
#
class WahaMessageMapping < ApplicationRecord
  belongs_to :channel, class_name: 'Channel::Waha', foreign_key: :channel_waha_id, inverse_of: :message_mappings
  belongs_to :message

  enum :direction, { incoming: 0, outgoing: 1 }
  # `edit` covers an edit mirror's own event; a future engine that reuses the
  # original message's id for it still gets a distinct row because event_type
  # is part of the unique identity (see the migration).
  enum :event_type, { message: 0, edit: 1, poll_vote: 2, call: 3 }

  validates :chat_jid, :external_id, presence: true
  # A friendly, non-racy check backed by index_waha_message_mappings_on_identity
  # for the actual guarantee — see the migration comment for why chat_jid and
  # event_type are part of the scope.
  validates :external_id, uniqueness: { scope: %i[channel_waha_id chat_jid event_type] }

  def self.find_mapping(channel:, chat_jid:, external_id:, event_type: :message)
    return nil if chat_jid.blank? || external_id.blank?

    where(channel: channel, chat_jid: chat_jid, external_id: external_id, event_type: event_type).first
  end

  # Creates canonical mapping within the caller's transaction, enforcing uniqueness.
  # Unlike `record!`, this raises on conflict so the enclosing message creation
  # transaction rolls back, guaranteeing zero duplicate messages in the DB.
  # rubocop:disable Metrics/ParameterLists
  def self.create_canonical!(channel:, message:, chat_jid:, external_id:, direction:, event_type: :message, participant_jid: nil, part: 0)
    return if chat_jid.blank? || external_id.blank?

    create!(
      channel: channel, message: message, chat_jid: chat_jid, external_id: external_id,
      direction: direction, event_type: event_type, participant_jid: participant_jid, part: part
    )
  end

  # Dual-write into the canonical mapping alongside the legacy source_id
  # correlation (Waha::Anchoring). Used by unmigrated flows like outgoing sends.
  def self.record!(channel:, message:, chat_jid:, external_id:, direction:, event_type: :message, participant_jid: nil, part: 0)
    return if chat_jid.blank? || external_id.blank?

    # Every call site dual-writes from inside the transaction that persists the
    # message itself. A real constraint violation here (not just a Ruby-level
    # exception) aborts the whole Postgres transaction, and rescuing in Ruby
    # alone wouldn't stop that — only rolling back to a savepoint does, which
    # is what requires_new: true gives us.
    ActiveRecord::Base.transaction(requires_new: true) do
      create!(
        channel: channel, message: message, chat_jid: chat_jid, external_id: external_id,
        direction: direction, event_type: event_type, participant_jid: participant_jid, part: part
      )
    end
  rescue StandardError => e
    Rails.logger.error "[WAHA] canonical mapping write failed for message #{message.id}: #{e.message}"
    nil
  end
  # rubocop:enable Metrics/ParameterLists
end
