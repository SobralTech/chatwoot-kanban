class AddActiveToKanbanConversationCardUniqueIndex < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    remove_index :kanban_cards, name: 'index_kanban_cards_on_conversation_subject_unique', algorithm: :concurrently

    add_index :kanban_cards,
              [:kanban_board_id, :conversation_id, :inbox_id, :normalized_subject],
              unique: true,
              where: "active = true AND origin = 'conversation' AND conversation_id IS NOT NULL AND normalized_subject IS NOT NULL",
              name: 'index_kanban_cards_on_conversation_subject_unique',
              algorithm: :concurrently
  end

  def down
    remove_index :kanban_cards, name: 'index_kanban_cards_on_conversation_subject_unique', algorithm: :concurrently

    add_index :kanban_cards,
              [:kanban_board_id, :conversation_id, :inbox_id, :normalized_subject],
              unique: true,
              where: "origin = 'conversation' AND conversation_id IS NOT NULL AND normalized_subject IS NOT NULL",
              name: 'index_kanban_cards_on_conversation_subject_unique',
              algorithm: :concurrently
  end
end
