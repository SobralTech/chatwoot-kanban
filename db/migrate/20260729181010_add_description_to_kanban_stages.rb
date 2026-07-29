class AddDescriptionToKanbanStages < ActiveRecord::Migration[7.1]
  def change
    add_column :kanban_stages, :description, :text
  end
end
