namespace :kanban_automations do
  desc 'Delete Kanban automation logs older than the retention period'
  task purge_logs: :environment do
    KanbanAutomations::PurgeLogsJob.perform_now
  end
end
