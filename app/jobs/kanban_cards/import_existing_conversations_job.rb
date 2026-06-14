class KanbanCards::ImportExistingConversationsJob < ApplicationJob
  queue_as :low

  def perform(account_id, kanban_board_id, ignore_groups: false)
    account = Account.find_by(id: account_id)
    kanban_board = KanbanBoard.active.find_by(id: kanban_board_id, account_id: account_id)
    return if account.blank? || kanban_board.blank?

    KanbanCards::ImportExistingConversationsService.new(
      account: account,
      kanban_board: kanban_board,
      ignore_groups: ignore_groups
    ).perform!
  end
end
