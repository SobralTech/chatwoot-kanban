class KanbanCards::ImportExistingConversationsJob < ApplicationJob
  queue_as :low

  def perform(account_id, kanban_board_id, ignore_groups: false, entry_rule_id: nil)
    account = Account.find_by(id: account_id)
    kanban_board = KanbanBoard.active.find_by(id: kanban_board_id, account_id: account_id)
    return if account.blank? || kanban_board.blank?

    KanbanCards::ImportExistingConversationsService.new(
      account: account,
      kanban_board: kanban_board,
      ignore_groups: ignore_groups,
      entry_rule: kanban_board.kanban_board_entry_rules.find_by(id: entry_rule_id)
    ).perform!
  end
end
