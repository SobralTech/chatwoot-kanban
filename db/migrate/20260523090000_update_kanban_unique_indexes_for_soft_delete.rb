class UpdateKanbanUniqueIndexesForSoftDelete < ActiveRecord::Migration[7.1]
  def change
    remove_index :kanban_boards, [:account_id, :name]
    add_index :kanban_boards, [:account_id, :name],
              unique: true,
              where: 'active = true',
              name: 'index_active_kanban_boards_on_account_id_and_name'

    remove_index :kanban_stages, [:kanban_board_id, :name]
    add_index :kanban_stages, [:kanban_board_id, :name],
              unique: true,
              where: 'active = true',
              name: 'index_active_kanban_stages_on_board_id_and_name'
  end
end
