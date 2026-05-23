class CreateKanbanStages < ActiveRecord::Migration[7.1]
  def change
    create_table :kanban_stages do |t|
      t.references :account, null: false, index: true
      t.references :kanban_board, null: false, index: true
      t.string :name, null: false
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :kanban_stages, [:kanban_board_id, :name], unique: true
    add_index :kanban_stages, [:kanban_board_id, :position]
    add_index :kanban_stages, [:account_id, :active]
  end
end
