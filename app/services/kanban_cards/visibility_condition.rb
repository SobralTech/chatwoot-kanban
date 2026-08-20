# Which cards a user may see at all, before the request asks for anything. An
# administrator sees the whole board, an agent bot only conversation cards, and an
# agent only what their inboxes and teams reach.
class KanbanCards::VisibilityCondition
  def initialize(account:, user:, account_user: nil)
    @account = account
    @user = user
    @account_user = account_user
  end

  def call
    return manual_card_condition.or(valid_conversation_card_condition) if administrator?
    return valid_conversation_card_condition if user.is_a?(AgentBot)

    agent_visibility_condition
  end

  private

  attr_reader :account, :user

  def agent_visibility_condition
    conditions = []
    conditions << accessible_manual_card_condition if visible_inbox_ids.present?
    conditions << accessible_conversation_card_condition if conversation_access_condition

    or_condition(conditions) || card_table[:id].eq(nil)
  end

  def accessible_manual_card_condition
    manual_card_condition.and(card_table[:inbox_id].in(visible_inbox_ids))
  end

  def accessible_conversation_card_condition
    valid_conversation_card_condition.and(conversation_access_condition)
  end

  def conversation_access_condition
    @conversation_access_condition ||= or_condition(conversation_access_conditions)
  end

  def conversation_access_conditions
    conditions = []
    conditions << conversation_table[:inbox_id].in(visible_inbox_ids) if visible_inbox_ids.present?
    conditions << conversation_table[:team_id].in(visible_team_ids) if visible_team_ids.present?
    conditions
  end

  def valid_conversation_card_condition
    condition = card_table[:conversation_id].not_eq(nil)
    condition = condition.and(conversation_table[:account_id].eq(account.id))
    condition = condition.and(conversation_table[:contact_id].eq(card_table[:contact_id]))
    condition.and(conversation_table[:inbox_id].eq(card_table[:inbox_id]))
  end

  def manual_card_condition
    card_table[:conversation_id].eq(nil)
  end

  def or_condition(conditions)
    conditions.reduce { |condition, next_condition| condition.or(next_condition) }
  end

  def visible_inbox_ids
    @visible_inbox_ids ||= user.inboxes.where(account_id: account.id).pluck(:id)
  end

  def visible_team_ids
    @visible_team_ids ||= user.teams.where(account_id: account.id).pluck(:id)
  end

  def administrator?
    account_user&.administrator?
  end

  def account_user
    return unless user.respond_to?(:account_users)

    @account_user ||= user.account_users.find_by(account: account)
  end

  def card_table
    KanbanCard.arel_table
  end

  def conversation_table
    Conversation.arel_table
  end
end
