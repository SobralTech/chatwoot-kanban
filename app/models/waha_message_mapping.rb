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
  belongs_to :anchor_message, class_name: 'Message', optional: true

  scope :resolved, -> { where(ambiguous: false) }

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

    matches = where(channel: channel, chat_jid: Waha::Anchoring.chat_jids(channel, chat_jid),
                    external_id: external_id, event_type: event_type).to_a
    return nil if matches.any?(&:ambiguous?)
    return matches.first if matches.map(&:message_id).uniq.size <= 1

    raise CustomExceptions::Waha::AmbiguousIdentity, "channel=#{channel.id} external_id=#{external_id} matches multiple messages"
  end

  # Creates canonical mapping within the caller's transaction, enforcing uniqueness.
  # Conflicts roll back the enclosing message creation transaction.
  # rubocop:disable Metrics/ParameterLists
  def self.create_canonical!(channel:, message:, chat_jid:, external_id:, direction:, event_type: :message, participant_jid: nil, part: 0,
                             provider_id: nil, anchor_message: nil)
    create!(
      channel: channel, message: message, chat_jid: chat_jid, external_id: external_id,
      direction: direction, event_type: event_type, participant_jid: participant_jid, part: part,
      provider_id: provider_id || [direction.to_s == 'outgoing', chat_jid, external_id, participant_jid].compact.join('_'),
      anchor_message: anchor_message
    )
  end

  # rubocop:enable Metrics/ParameterLists
end
