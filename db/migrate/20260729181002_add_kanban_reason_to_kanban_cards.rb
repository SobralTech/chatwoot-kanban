class AddKanbanReasonToKanbanCards < ActiveRecord::Migration[7.1]
  def change
    add_column :kanban_cards, :kanban_reason_id, :bigint
    add_index :kanban_cards, :kanban_reason_id
  end
end
