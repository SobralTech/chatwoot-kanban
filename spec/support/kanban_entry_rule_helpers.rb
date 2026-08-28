module KanbanEntryRuleHelpers
  # Narrows a board to the given inboxes the way the product does: an active entry rule
  # naming them. Passing none leaves the board narrowed to nothing.
  def restrict_board_to_inboxes(kanban_board, *inboxes)
    rule = create(
      :kanban_board_entry_rule, :selected_inboxes,
      account: kanban_board.account, kanban_board: kanban_board
    )
    inboxes.each do |inbox|
      create(:kanban_board_entry_rule_inbox, account: kanban_board.account, kanban_board_entry_rule: rule, inbox: inbox)
    end
    rule
  end
end
