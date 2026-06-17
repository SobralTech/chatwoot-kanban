# == Schema Information
#
# Table name: conversation_pins
#
#  id              :bigint           not null, primary key
#  pin_type        :integer          default("personal"), not null
#  pinned_at       :datetime         not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  conversation_id :bigint           not null
#  user_id         :bigint           not null
#
# Indexes
#
#  idx_conv_pins_account_unique                (conversation_id,account_id) UNIQUE WHERE (pin_type = 1)
#  idx_conv_pins_personal_unique               (conversation_id,user_id) UNIQUE WHERE (pin_type = 0)
#  index_conversation_pins_on_account_id       (account_id)
#  index_conversation_pins_on_conversation_id  (conversation_id)
#  index_conversation_pins_on_user_id          (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (conversation_id => conversations.id)
#  fk_rails_...  (user_id => users.id)
#
class ConversationPin < ApplicationRecord
  enum pin_type: { personal: 0, account: 1 }

  belongs_to :account
  belongs_to :conversation
  belongs_to :user

  validates :pinned_at, presence: true
  validates :conversation_id,
            uniqueness: { scope: :user_id, message: 'already pinned by this user' },
            if: :personal?
  validates :conversation_id,
            uniqueness: { scope: :account_id, message: 'already pinned for this account' },
            if: :account?
end
