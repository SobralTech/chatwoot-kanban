class CreateKanbanCards < ActiveRecord::Migration[7.1]
  def change
    create_table :kanban_cards do |t|
      t.references :account, null: false, index: false
      t.references :kanban_board, null: false, index: false
      t.references :kanban_stage, null: false, index: false
      t.references :contact, null: false, index: false
      t.references :inbox, null: false, index: false
      t.references :conversation, null: true, index: false
      t.string :subject
      t.string :normalized_subject
      t.string :origin, null: false
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_kanban_card_lookup_indexes
    add_kanban_card_unique_indexes
  end

  private

  def add_kanban_card_lookup_indexes
    add_index :kanban_cards, [:account_id, :active]
    add_index :kanban_cards, [:kanban_board_id, :active]
    add_index :kanban_cards, [:kanban_board_id, :kanban_stage_id, :position], name: 'index_kanban_cards_on_board_stage_position'
    add_index :kanban_cards, [:account_id, :contact_id]
    add_index :kanban_cards, [:account_id, :inbox_id]
    add_index :kanban_cards, :conversation_id
  end

  def add_kanban_card_unique_indexes
    add_index :kanban_cards, [:kanban_board_id, :conversation_id],
              unique: true,
              where: "active = true AND conversation_id IS NOT NULL AND origin = 'conversation'",
              name: 'index_active_kanban_cards_on_board_and_conversation'
    add_index :kanban_cards, [:kanban_board_id, :contact_id, :inbox_id, :normalized_subject],
              unique: true,
              where: "active = true AND origin = 'manual' AND normalized_subject IS NOT NULL",
              name: 'index_active_manual_kanban_cards_unique_subject'
  end
end
