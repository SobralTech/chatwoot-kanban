class AddAllowAgentKanbanBoardCreationToAccounts < ActiveRecord::Migration[7.1]
  def change
    add_column :accounts, :allow_agent_kanban_board_creation, :boolean, null: false, default: true
  end
end
