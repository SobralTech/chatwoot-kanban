class CreateKanbanCustomFields < ActiveRecord::Migration[7.1]
  def change
    create_table :kanban_custom_fields do |t|
      t.references :account, null: false, foreign_key: true
      t.references :kanban_board, null: false, foreign_key: true
      t.string :key, null: false
      t.integer :field_type, null: false, default: 0
      t.boolean :multiple, null: false, default: false
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :kanban_custom_fields, [:kanban_board_id, :key],
              unique: true, where: 'active = true', name: 'index_active_kanban_custom_fields_on_board_id_and_key'
  end
end
