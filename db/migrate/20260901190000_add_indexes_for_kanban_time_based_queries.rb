class AddIndexesForKanbanTimeBasedQueries < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :kanban_cards, [:kanban_board_id, :due_at],
              where: 'active = TRUE',
              name: 'idx_active_kanban_cards_board_due_at',
              algorithm: :concurrently
    add_index :kanban_cards, [:kanban_board_id, :stage_entered_at],
              where: 'active = TRUE',
              name: 'idx_active_kanban_cards_board_stage_entered_at',
              algorithm: :concurrently
  end
end
