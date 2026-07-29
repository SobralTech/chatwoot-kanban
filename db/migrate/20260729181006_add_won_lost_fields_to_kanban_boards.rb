class AddWonLostFieldsToKanbanBoards < ActiveRecord::Migration[7.1]
  def change
    add_column :kanban_boards, :won_stage_id, :bigint
    add_column :kanban_boards, :lost_stage_id, :bigint
    add_column :kanban_boards, :lost_reason_required, :boolean, null: false, default: false

    add_index :kanban_boards, :won_stage_id
    add_index :kanban_boards, :lost_stage_id
  end
end
