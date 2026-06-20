# == Schema Information
#
# Table name: kanban_card_assignees
#
#  id             :bigint           not null, primary key
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  account_id     :bigint           not null
#  kanban_card_id :bigint           not null
#  user_id        :bigint           not null
#
# Indexes
#
#  index_kanban_card_assignees_on_account_id                  (account_id)
#  index_kanban_card_assignees_on_kanban_card_id              (kanban_card_id)
#  index_kanban_card_assignees_on_kanban_card_id_and_user_id  (kanban_card_id,user_id) UNIQUE
#  index_kanban_card_assignees_on_user_id                     (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (kanban_card_id => kanban_cards.id)
#  fk_rails_...  (user_id => users.id)
#
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
