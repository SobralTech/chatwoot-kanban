# The automation log keeps three months of history: it is an audit trail, not an archive,
# and it grows with every rule that fires.
class KanbanAutomations::PurgeLogsJob < ApplicationJob
  queue_as :purgable

  RETENTION = 90.days

  def perform
    KanbanAutomationLog.where(created_at: ...RETENTION.ago).delete_all
  end
end
