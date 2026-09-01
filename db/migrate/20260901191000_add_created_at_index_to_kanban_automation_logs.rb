class AddCreatedAtIndexToKanbanAutomationLogs < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :kanban_automation_logs, :created_at,
              name: 'index_kanban_automation_logs_on_created_at',
              algorithm: :concurrently
  end
end
