class AddSchedulingFieldsToKanbanCards < ActiveRecord::Migration[7.1]
  def change
    add_column :kanban_cards, :starts_at, :datetime
    add_column :kanban_cards, :due_at, :datetime
  end
end
