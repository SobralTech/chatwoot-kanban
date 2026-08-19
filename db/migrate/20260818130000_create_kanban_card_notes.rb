class CreateKanbanCardNotes < ActiveRecord::Migration[7.1]
  def change
    create_table :kanban_card_notes do |t|
      t.references :account, null: false, index: true, foreign_key: true
      t.references :kanban_card, null: false, index: true, foreign_key: true
      t.references :user, null: true, foreign_key: { on_delete: :nullify }
      t.text :content, null: false
      t.timestamps
    end

    add_index :kanban_card_notes, [:kanban_card_id, :created_at]
  end
end
