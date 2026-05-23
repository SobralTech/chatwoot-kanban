class KanbanBoardPolicy < ApplicationPolicy
  def index?
    administrator? || agent?
  end

  def show?
    administrator? || agent?
  end

  def create?
    administrator?
  end

  def update?
    administrator?
  end

  def destroy?
    administrator?
  end

  private

  def administrator?
    account_user&.administrator?
  end

  def agent?
    account_user&.agent?
  end
end
