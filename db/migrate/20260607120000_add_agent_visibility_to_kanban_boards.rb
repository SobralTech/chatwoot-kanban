class AddAgentVisibilityToKanbanBoards < ActiveRecord::Migration[7.1]
  def change
    add_column :kanban_boards, :visibility_mode, :string, null: false, default: 'all_agents'

    create_table :kanban_board_members do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.references :kanban_board, null: false, foreign_key: true, index: false
      t.references :user, null: false, foreign_key: true, index: false

      t.timestamps

      t.index [:kanban_board_id, :user_id], unique: true
      t.index [:account_id, :user_id, :kanban_board_id], name: 'index_kanban_board_members_on_account_user_board'
    end
  end
end
