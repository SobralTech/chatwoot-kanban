class KanbanCardNotePolicy < ApplicationPolicy
  def update?
    manageable?
  end

  def destroy?
    manageable?
  end

  private

  def manageable?
    account_user&.administrator? || record.user_id == user&.id
  end
end
