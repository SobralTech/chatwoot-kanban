class CreateKanbanCardEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :kanban_card_events do |t|
      t.references :account, null: false, index: true
      t.references :kanban_card, null: false, index: true
      t.references :kanban_board, null: false
      t.references :user, null: true
      t.string :event_type, null: false
      t.jsonb :metadata, null: false, default: {}
      t.datetime :created_at, null: false
    end

    add_index :kanban_card_events, [:kanban_card_id, :created_at]
    add_index :kanban_card_events, [:kanban_board_id, :event_type, :created_at]
  end
end
