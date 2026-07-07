class SwitchKanbanCardsToHardDelete < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    execute 'DELETE FROM kanban_cards WHERE active = false'

    remove_column :kanban_cards, :explicitly_deleted if column_exists?(:kanban_cards, :explicitly_deleted)

    remove_index :kanban_cards, name: 'index_kanban_cards_on_conversation_subject_unique', algorithm: :concurrently

    add_index :kanban_cards,
              %i[kanban_board_id conversation_id inbox_id normalized_subject],
              unique: true,
              where: "origin = 'conversation' AND conversation_id IS NOT NULL AND normalized_subject IS NOT NULL",
              name: 'index_kanban_cards_on_conversation_subject_unique',
              algorithm: :concurrently
  end

  def down
    remove_index :kanban_cards, name: 'index_kanban_cards_on_conversation_subject_unique', algorithm: :concurrently

    add_index :kanban_cards,
              %i[kanban_board_id conversation_id inbox_id normalized_subject],
              unique: true,
              where: "origin = 'conversation' AND conversation_id IS NOT NULL AND normalized_subject IS NOT NULL",
              name: 'index_kanban_cards_on_conversation_subject_unique',
              algorithm: :concurrently

    add_column :kanban_cards, :explicitly_deleted, :boolean, default: false, null: false
  end
end
