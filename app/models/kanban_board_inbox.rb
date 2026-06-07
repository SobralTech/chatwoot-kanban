# == Schema Information
#
# Table name: kanban_board_inboxes
#
#  id              :bigint           not null, primary key
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  inbox_id        :bigint           not null
#  kanban_board_id :bigint           not null
#
# Indexes
#
#  index_kanban_board_inboxes_on_account_inbox_board           (account_id,inbox_id,kanban_board_id)
#  index_kanban_board_inboxes_on_kanban_board_id_and_inbox_id  (kanban_board_id,inbox_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (inbox_id => inboxes.id)
#  fk_rails_...  (kanban_board_id => kanban_boards.id)
#
class KanbanBoardInbox < ApplicationRecord
  belongs_to :account
  belongs_to :kanban_board
  belongs_to :inbox

  validates :inbox_id, uniqueness: { scope: :kanban_board_id }
  validate :validate_board_account
  validate :validate_inbox_account

  private

  def validate_board_account
    return if kanban_board.blank? || account_id == kanban_board.account_id

    errors.add(:account_id, :invalid)
  end

  def validate_inbox_account
    return if inbox.blank? || account_id == inbox.account_id

    errors.add(:account_id, :invalid)
  end
end
