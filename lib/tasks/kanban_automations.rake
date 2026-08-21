namespace :kanban_automations do
  desc 'Purge Kanban automation logs older than 90 days'
  task purge_logs: :environment do
    KanbanAutomationLog.where('created_at < ?', 90.days.ago).delete_all
  end
end
