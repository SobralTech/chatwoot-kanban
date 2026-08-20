class CreateKanbanAutomationRules < ActiveRecord::Migration[7.1]
  def change
    create_table :kanban_automation_rules do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.references :kanban_board, null: false, foreign_key: true, index: true
      t.string :name, null: false
      t.text :description
      t.string :event_name, null: false
      t.jsonb :conditions, null: false, default: []
      t.jsonb :actions, null: false, default: []
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: false
      t.boolean :dry_run, null: false, default: true
      t.boolean :stop_after_match, null: false, default: false
      t.references :created_by, null: true, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :kanban_automation_rules, [:kanban_board_id, :event_name, :active],
              name: 'index_kanban_automation_rules_on_board_event_active'
  end
end
