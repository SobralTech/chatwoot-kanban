class UpdateConversationKanbanCardUniqueIndex < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    add_index :kanban_cards, [:kanban_board_id, :conversation_id],
              unique: true,
              where: "origin = 'conversation' AND conversation_id IS NOT NULL",
              name: 'index_kanban_cards_on_board_and_conversation_origin_unique',
              algorithm: :concurrently
    remove_index :kanban_cards, name: 'index_active_kanban_cards_on_board_and_conversation', algorithm: :concurrently
  end

  def down
    add_index :kanban_cards, [:kanban_board_id, :conversation_id],
              unique: true,
              where: "active = true AND conversation_id IS NOT NULL AND origin = 'conversation'",
              name: 'index_active_kanban_cards_on_board_and_conversation',
              algorithm: :concurrently
    remove_index :kanban_cards, name: 'index_kanban_cards_on_board_and_conversation_origin_unique', algorithm: :concurrently
  end
end
