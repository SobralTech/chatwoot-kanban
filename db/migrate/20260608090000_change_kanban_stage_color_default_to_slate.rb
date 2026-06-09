class ChangeKanbanStageColorDefaultToSlate < ActiveRecord::Migration[7.1]
  def change
    change_column_default :kanban_stages, :color, from: 'blue', to: 'slate'
  end
end
