class UpdateConversationKanbanCardUniqueIndex < ActiveRecord::Migration[7.1]
  def up
    remove_index :kanban_cards, name: 'index_active_kanban_cards_on_board_and_conversation'
    add_index :kanban_cards, [:kanban_board_id, :conversation_id],
              unique: true,
              where: "origin = 'conversation' AND conversation_id IS NOT NULL",
              name: 'index_kanban_cards_on_board_and_conversation_origin_unique'
  end

  def down
    remove_index :kanban_cards, name: 'index_kanban_cards_on_board_and_conversation_origin_unique'
    add_index :kanban_cards, [:kanban_board_id, :conversation_id],
              unique: true,
              where: "active = true AND conversation_id IS NOT NULL AND origin = 'conversation'",
              name: 'index_active_kanban_cards_on_board_and_conversation'
  end
end
