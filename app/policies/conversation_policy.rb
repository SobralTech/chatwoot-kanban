class ConversationPolicy < ApplicationPolicy
  def index?
    true
  end

  def destroy?
    administrator?
  end

  def show?
    administrator? || agent_bot? || agent_can_view_conversation?
  end

  private

  def agent_can_view_conversation?
    (inbox_access? || team_access?) && access_list_allowed?
  end

  def base_agent_can_view_conversation?
    inbox_access? || team_access?
  end

  def administrator?
    account_user&.administrator?
  end

  def agent_bot?
    user.is_a?(AgentBot)
  end

  def access_list_allowed?
    return false if record.admins_only?
    return access_listed? if record.selected_agents?

    true
  end

  def access_listed?
    return batch_context.access_listed?(user.id) if batch_context

    record.conversation_access_users.exists?(user_id: user.id)
  end

  def inbox_access?
    return batch_context.inbox_member?(user.id) if batch_context

    user.inboxes.where(account_id: account&.id).exists?(id: record.inbox_id)
  end

  def team_access?
    return false if record.team_id.blank?
    return batch_context.team_member?(user.id) if batch_context

    user.teams.where(account_id: account&.id).exists?(id: record.team_id)
  end

  def assigned_to_user?
    record.assignee_id == user.id
  end

  def participant?
    return batch_context.participant?(user.id) if batch_context

    record.conversation_participants.exists?(user_id: user.id)
  end

  # Set when many users are authorized against the same conversation; see ConversationPolicy::BatchContext.
  def batch_context
    user_context[:batch_context]
  end
end

ConversationPolicy.prepend_mod_with('ConversationPolicy')
