# == Schema Information
#
# Table name: conversation_pins
#
#  id              :bigint           not null, primary key
#  pinned_at       :datetime         not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  conversation_id :bigint           not null
#  user_id         :bigint           not null
#
# Indexes
#
#  idx_conv_pins_unique                        (conversation_id) UNIQUE
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
  belongs_to :account
  belongs_to :conversation
  belongs_to :user

  validates :pinned_at, presence: true
  validates :conversation_id, uniqueness: true
end
