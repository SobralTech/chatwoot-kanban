# == Schema Information
#
# Table name: kanban_board_members
#
#  id              :bigint           not null, primary key
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  kanban_board_id :bigint           not null
#  user_id         :bigint           not null
#
# Indexes
#
#  index_kanban_board_members_on_account_user_board           (account_id,user_id,kanban_board_id)
#  index_kanban_board_members_on_kanban_board_id_and_user_id  (kanban_board_id,user_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (kanban_board_id => kanban_boards.id)
#  fk_rails_...  (user_id => users.id)
#
class KanbanBoardMember < ApplicationRecord
  belongs_to :account
  belongs_to :kanban_board
  belongs_to :user

  validates :user_id, uniqueness: { scope: :kanban_board_id }
  validate :validate_board_account
  validate :validate_user_account

  private

  def validate_board_account
    return if kanban_board.blank? || account_id == kanban_board.account_id

    errors.add(:account_id, :invalid)
  end

  def validate_user_account
    return if user.blank? || account.blank?
    return if AccountUser.exists?(account_id: account_id, user_id: user_id)

    errors.add(:user_id, :invalid)
  end
end
