class AddExplicitlyDeletedToKanbanCards < ActiveRecord::Migration[7.1]
  def change
    add_column :kanban_cards, :explicitly_deleted, :boolean, default: false, null: false
  end
end
