class KanbanCardAssignee < ApplicationRecord
  belongs_to :account
  belongs_to :kanban_card
  belongs_to :user

  validates :user_id, uniqueness: { scope: :kanban_card_id }
  validate :validate_account_consistency
  validate :validate_user_assignable

  private

  def validate_account_consistency
    return if kanban_card.blank? || account_id == kanban_card.account_id

    errors.add(:account_id, :invalid)
  end

  def validate_user_assignable
    return if kanban_card.blank? || user.blank?
    return if kanban_card.kanban_board.assignable_users.exists?(id: user.id)

    errors.add(:user, :invalid)
  end
end
