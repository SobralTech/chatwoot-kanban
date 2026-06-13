class KanbanBoardPolicy < ApplicationPolicy
  def index?
    administrator? || agent?
  end

  def show?
    administrator? || agent?
  end

  def create?
    administrator? || agent?
  end

  def update?
    administrator?
  end

  def destroy?
    administrator?
  end

  def visible?
    return false unless record.is_a?(KanbanBoard)
    return false unless record.active?
    return false unless account_user
    return true if administrator?
    return true if record.visibility_mode == 'all_agents'

    record.kanban_board_members.exists?(user_id: user.id)
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless account_user

      base = scope.active.where(account_id: account.id)
      return base if account_user.administrator?

      member_board_ids = KanbanBoardMember.where(user_id: user.id).select(:kanban_board_id)
      base.where(visibility_mode: 'all_agents').or(
        base.where(visibility_mode: 'selected_agents', id: member_board_ids)
      )
    end
  end

  private

  def administrator?
    account_user&.administrator?
  end

  def agent?
    account_user&.agent?
  end
end
