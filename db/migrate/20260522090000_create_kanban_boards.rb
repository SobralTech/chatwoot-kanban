class CreateKanbanBoards < ActiveRecord::Migration[7.1]
  def change
    create_table :kanban_boards do |t|
      t.references :account, null: false, index: true
      t.string :name, null: false
      t.text :description
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :kanban_boards, [:account_id, :name], unique: true
    add_index :kanban_boards, [:account_id, :position]
    add_index :kanban_boards, [:account_id, :active]
  end
end
