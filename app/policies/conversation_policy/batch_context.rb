# Preloads every membership lookup ConversationPolicy performs, so authorizing a whole
# account's users against one conversation costs a constant number of queries instead of
# a handful per user. Built once per conversation and passed through the user context.
class ConversationPolicy::BatchContext
  def initialize(account, conversation)
    @account = account
    @conversation = conversation
  end

  def account_user_for(user_id)
    account_users_by_user_id[user_id]
  end

  def inbox_member?(user_id)
    inbox_user_ids.include?(user_id)
  end

  def team_member?(user_id)
    team_user_ids.include?(user_id)
  end

  def access_listed?(user_id)
    access_user_ids.include?(user_id)
  end

  def participant?(user_id)
    participant_user_ids.include?(user_id)
  end

  private

  def account_users_by_user_id
    @account_users_by_user_id ||= account_users_scope.index_by(&:user_id)
  end

  def account_users_scope
    scope = @account.account_users
    # custom_role is defined by the enterprise extension only.
    AccountUser.reflect_on_association(:custom_role) ? scope.includes(:custom_role) : scope
  end

  def inbox_user_ids
    @inbox_user_ids ||= InboxMember.where(inbox_id: @conversation.inbox_id).pluck(:user_id).to_set
  end

  def team_user_ids
    @team_user_ids ||= if @conversation.team_id.blank?
                         Set.new
                       else
                         TeamMember.where(team_id: @conversation.team_id).pluck(:user_id).to_set
                       end
  end

  def access_user_ids
    @access_user_ids ||= @conversation.conversation_access_users.pluck(:user_id).to_set
  end

  def participant_user_ids
    @participant_user_ids ||= @conversation.conversation_participants.pluck(:user_id).to_set
  end
end
