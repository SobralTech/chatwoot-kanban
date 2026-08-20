class KanbanAutomationRulePolicy < ApplicationPolicy
  def index?
    administrator?
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

  def toggle?
    administrator?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless account_user&.administrator?

      scope.where(account_id: account.id)
    end
  end

  private

  def administrator?
    account_user&.administrator?
  end
end
