class CreateKanbanAutomationLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :kanban_automation_logs do |t|
      t.references :account, null: false, index: true
      t.references :kanban_automation_rule, null: false, index: true,
                                            foreign_key: { on_delete: :cascade }
      t.references :kanban_card, null: true,
                                 foreign_key: { on_delete: :nullify }
      t.string :event_name, null: false
      t.string :status, null: false
      t.jsonb :details, null: false, default: {}
      t.datetime :created_at, null: false
    end

    add_index :kanban_automation_logs, [:kanban_automation_rule_id, :created_at],
              name: 'index_kanban_automation_logs_on_rule_and_created_at'
    add_index :kanban_automation_logs, [:kanban_card_id, :created_at],
              name: 'index_kanban_automation_logs_on_card_and_created_at'
  end
end
