# == Schema Information
#
# Table name: conversation_access_users
#
#  id              :bigint           not null, primary key
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  conversation_id :bigint           not null
#  user_id         :bigint           not null
#
# Indexes
#
#  idx_conversation_access_users_account_user       (account_id,user_id)
#  idx_conversation_access_users_unique             (conversation_id,user_id) UNIQUE
#  idx_conversation_access_users_user_conversation  (user_id,conversation_id)
#  index_conversation_access_users_on_user_id       (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (conversation_id => conversations.id)
#  fk_rails_...  (user_id => users.id)
#
class ConversationAccessUser < ApplicationRecord
  belongs_to :account
  belongs_to :conversation
  belongs_to :user

  validates :user_id, uniqueness: { scope: :conversation_id }
  validate :conversation_must_belong_to_account
  validate :user_must_be_agent

  def effective_access?
    return false unless account_user&.agent?

    Conversations::PermissionFilterService.new(Conversation.where(id: conversation_id), user, conversation.account).perform.exists?(conversation_id)
  end

  private

  def account_user
    @account_user ||= account.account_users.find_by(user_id: user_id)
  end

  def conversation_must_belong_to_account
    errors.add(:conversation, 'must belong to account') if conversation&.account_id != account_id
  end

  def user_must_be_agent
    errors.add(:user, 'must be an agent') unless account_user&.agent?
  end
end
