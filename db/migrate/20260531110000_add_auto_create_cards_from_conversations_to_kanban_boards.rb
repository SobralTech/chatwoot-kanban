class AddAutoCreateCardsFromConversationsToKanbanBoards < ActiveRecord::Migration[7.1]
  def change
    add_column :kanban_boards, :auto_create_cards_from_conversations, :boolean, null: false, default: false
  end
end
