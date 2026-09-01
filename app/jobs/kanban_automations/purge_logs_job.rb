# The automation log keeps three months of history: it is an audit trail, not an archive,
# and it grows with every rule that fires.
class KanbanAutomations::PurgeLogsJob < ApplicationJob
  queue_as :purgable

  RETENTION = 90.days
  BATCH_SIZE = 10_000

  def perform
    KanbanAutomationLog.where(created_at: ...RETENTION.ago).in_batches(of: BATCH_SIZE).delete_all
  end
end
