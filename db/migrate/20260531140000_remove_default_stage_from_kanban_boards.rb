class RemoveDefaultStageFromKanbanBoards < ActiveRecord::Migration[7.1]
  def change
    remove_reference :kanban_boards, :default_stage, index: true
  end
end
