# == Schema Information
#
# Table name: waha_contact_aliases
#
#  id               :bigint           not null, primary key
#  alias_type       :string           not null
#  value            :string           not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  channel_waha_id  :bigint           not null
#  contact_inbox_id :bigint           not null
#
# Indexes
#
#  index_waha_contact_aliases_on_channel_waha_id   (channel_waha_id)
#  index_waha_contact_aliases_on_contact_inbox_id  (contact_inbox_id)
#  index_waha_contact_aliases_on_identity          (channel_waha_id,alias_type,value) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (channel_waha_id => channel_waha.id) ON DELETE => cascade
#  fk_rails_...  (contact_inbox_id => contact_inboxes.id) ON DELETE => cascade
#
class WahaContactAlias < ApplicationRecord
  ALIAS_TYPES = %w[jid lid phone].freeze

  belongs_to :channel, class_name: 'Channel::Waha', foreign_key: :channel_waha_id, inverse_of: :contact_aliases
  belongs_to :contact_inbox

  before_validation :normalize_value

  validates :alias_type, inclusion: { in: ALIAS_TYPES }
  validates :value, presence: true, uniqueness: { scope: %i[channel_waha_id alias_type] }
  validates :value, format: { with: /\A\+[1-9]\d{1,14}\z/ }, if: -> { alias_type == 'phone' }

  private

  def normalize_value
    self.value = if alias_type == 'phone'
                   "+#{value.to_s.gsub(/\D/, '')}"
                 else
                   value.to_s.downcase
                 end
  end
end
