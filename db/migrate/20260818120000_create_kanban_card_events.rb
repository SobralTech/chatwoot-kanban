class CreateKanbanCardEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :kanban_card_events do |t|
      t.references :account, null: false, index: true, foreign_key: true
      # Nullable on purpose: `card_deleted` outlives the card row it describes.
      t.references :kanban_card, null: true, index: true, foreign_key: { on_delete: :nullify }
      t.references :kanban_board, null: false, foreign_key: true
      t.references :user, null: true, foreign_key: { on_delete: :nullify }
      t.string :event_type, null: false
      t.jsonb :metadata, null: false, default: {}
      t.datetime :created_at, null: false
    end

    add_index :kanban_card_events, [:kanban_card_id, :created_at]
    add_index :kanban_card_events, [:kanban_board_id, :event_type, :created_at]
  end
end
