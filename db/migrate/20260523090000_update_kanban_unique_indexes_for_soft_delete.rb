class UpdateKanbanUniqueIndexesForSoftDelete < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    add_index :kanban_boards, [:account_id, :name],
              unique: true,
              where: 'active = true',
              name: 'index_active_kanban_boards_on_account_id_and_name',
              algorithm: :concurrently
    remove_index :kanban_boards, name: 'index_kanban_boards_on_account_id_and_name', algorithm: :concurrently

    add_index :kanban_stages, [:kanban_board_id, :name],
              unique: true,
              where: 'active = true',
              name: 'index_active_kanban_stages_on_board_id_and_name',
              algorithm: :concurrently
    remove_index :kanban_stages, name: 'index_kanban_stages_on_kanban_board_id_and_name', algorithm: :concurrently
  end

  def down
    add_index :kanban_boards, [:account_id, :name],
              unique: true,
              name: 'index_kanban_boards_on_account_id_and_name',
              algorithm: :concurrently
    remove_index :kanban_boards, name: 'index_active_kanban_boards_on_account_id_and_name', algorithm: :concurrently

    add_index :kanban_stages, [:kanban_board_id, :name],
              unique: true,
              name: 'index_kanban_stages_on_kanban_board_id_and_name',
              algorithm: :concurrently
    remove_index :kanban_stages, name: 'index_active_kanban_stages_on_board_id_and_name', algorithm: :concurrently
  end
end
