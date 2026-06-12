class AddDescriptionToKanbanCards < ActiveRecord::Migration[7.1]
  def change
    add_column :kanban_cards, :description, :text
  end
end
