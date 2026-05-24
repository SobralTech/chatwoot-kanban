class AddColorToKanbanStages < ActiveRecord::Migration[7.1]
  def change
    add_column :kanban_stages, :color, :string, null: false, default: 'blue'
  end
end
