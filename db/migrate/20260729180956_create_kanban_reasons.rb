class CreateKanbanReasons < ActiveRecord::Migration[7.1]
  def change
    create_table :kanban_reasons do |t|
      t.references :account, null: false, foreign_key: true
      t.references :kanban_board, null: false, foreign_key: true
      t.string :title, null: false
      t.text :description
      t.integer :reason_type, null: false, default: 0
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true

      t.timestamps
    end
  end
end
