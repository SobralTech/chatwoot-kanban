class AddInboxScopeToKanbanBoards < ActiveRecord::Migration[7.1]
  def change
    add_column :kanban_boards, :inbox_scope_mode, :string, null: false, default: 'all_inboxes'

    create_table :kanban_board_inboxes do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.references :kanban_board, null: false, foreign_key: true, index: false
      t.references :inbox, null: false, foreign_key: true, index: false

      t.timestamps

      t.index [:kanban_board_id, :inbox_id], unique: true
      t.index [:account_id, :inbox_id, :kanban_board_id], name: 'index_kanban_board_inboxes_on_account_inbox_board'
    end
  end
end
