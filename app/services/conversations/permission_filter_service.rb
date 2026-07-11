class Conversations::PermissionFilterService
  attr_reader :conversations, :user, :account

  def initialize(conversations, user, account)
    @conversations = conversations
    @user = user
    @account = account
  end

  def perform
    return conversations if user.is_a?(AgentBot)
    return conversations if user_role == 'administrator'

    access_list_restricted(accessible_conversations)
  end

  def access_list_restricted(scope)
    scope.where(access_mode: :all_agents).or(scope.where(access_mode: :selected_agents, id: allowed_conversation_ids))
  end

  private

  def allowed_conversation_ids
    ConversationAccessUser.where(account_id: account.id, user_id: user.id).select(:conversation_id)
  end

  def accessible_conversations
    conversations.where(inbox: user.inboxes.where(account_id: account.id))
  end

  def account_user
    AccountUser.find_by(account_id: account.id, user_id: user.id)
  end

  def user_role
    account_user&.role
  end
end

Conversations::PermissionFilterService.prepend_mod_with('Conversations::PermissionFilterService')
