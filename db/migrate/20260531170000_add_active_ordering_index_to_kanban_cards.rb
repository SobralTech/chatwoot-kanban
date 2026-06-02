class AddActiveOrderingIndexToKanbanCards < ActiveRecord::Migration[7.1]
  def change
    add_index :kanban_cards,
              [:kanban_board_id, :kanban_stage_id, :position, :created_at, :id],
              where: 'active = true',
              name: 'index_active_kanban_cards_on_board_stage_order'
  end
end
