class CreateKanbanCardAssignees < ActiveRecord::Migration[7.1]
  def change
    create_table :kanban_card_assignees do |t|
      t.references :account, null: false, foreign_key: true
      t.references :kanban_card, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end

    add_index :kanban_card_assignees, %i[kanban_card_id user_id], unique: true
  end
end
