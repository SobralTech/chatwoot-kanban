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
    restricted_access_users = ConversationAccessUser.where(account_id: account.id)
    return scope unless restricted_access_users.exists?

    restricted_ids = restricted_access_users.select(:conversation_id)
    allowed_ids = restricted_access_users.where(user_id: user.id).select(:conversation_id)

    scope.where.not(id: restricted_ids).or(scope.where(id: allowed_ids))
  end

  private

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
