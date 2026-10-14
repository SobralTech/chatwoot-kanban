class Conversations::PermissionFilterService
  attr_reader :conversations, :user, :account

  def initialize(conversations, user, account, plan_hint_selective_filter: false)
    @conversations = conversations
    @user = user
    @account = account
    @plan_hint_selective_filter = plan_hint_selective_filter
  end

  def perform
    return conversations if unrestricted?

    access_list_restricted(accessible_conversations)
  end

  # True when the user can see every conversation in the account. Callers use this to skip
  # building a subquery that would span the whole conversations table without filtering anything.
  def unrestricted?
    user.is_a?(AgentBot) || user_role == 'administrator'
  end

  def access_list_restricted(scope)
    scope.where(access_mode: :all_agents).or(scope.where(access_mode: :selected_agents, id: allowed_conversation_ids))
  end

  private

  def allowed_conversation_ids
    ConversationAccessUser.where(account_id: account.id, user_id: user.id).select(:conversation_id)
  end

  def accessible_conversations
    return hinted_accessible_conversations if @plan_hint_selective_filter

    conversations.where(inbox: user.inboxes.where(account_id: account.id))
  end

  # Same rows as accessible_conversations. `inbox_id + 0` keeps the planner from
  # driving the query through an inbox scan, which it grossly misestimates when a
  # highly selective filter (e.g. labels) is present on large accounts (CW-7787).
  def hinted_accessible_conversations
    conversations.where(
      '(conversations.inbox_id + 0) IN (
        SELECT inbox_members.inbox_id FROM inbox_members
        INNER JOIN inboxes ON inboxes.id = inbox_members.inbox_id
        WHERE inbox_members.user_id = :user_id AND inboxes.account_id = :account_id
      )',
      user_id: user.id, account_id: account.id
    )
  end

  def account_user
    return @account_user if defined?(@account_user)

    @account_user = AccountUser.find_by(account_id: account.id, user_id: user.id)
  end

  def user_role
    account_user&.role
  end
end

Conversations::PermissionFilterService.prepend_mod_with('Conversations::PermissionFilterService')
