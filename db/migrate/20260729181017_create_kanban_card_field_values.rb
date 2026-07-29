class CreateKanbanCardFieldValues < ActiveRecord::Migration[7.1]
  def change
    create_table :kanban_card_field_values do |t|
      t.references :account, null: false, foreign_key: true
      t.references :kanban_card, null: false, foreign_key: true
      t.references :kanban_custom_field, null: false, foreign_key: true
      t.jsonb :value, null: false, default: []

      t.timestamps
    end

    add_index :kanban_card_field_values, [:kanban_card_id, :kanban_custom_field_id],
              unique: true, name: 'index_kanban_card_field_values_on_card_and_field'
  end
end
