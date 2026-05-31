class AddDefaultStageToKanbanBoards < ActiveRecord::Migration[7.1]
  def change
    add_reference :kanban_boards, :default_stage, null: true, index: true
  end
end
