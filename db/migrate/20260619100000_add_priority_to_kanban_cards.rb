class AddPriorityToKanbanCards < ActiveRecord::Migration[7.1]
  def change
    add_column :kanban_cards, :priority, :integer
  end
end
