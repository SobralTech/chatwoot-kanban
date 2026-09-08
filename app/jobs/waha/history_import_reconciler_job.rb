class Waha::HistoryImportReconcilerJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Channel::Waha.where("import_state ->> 'status' IN (?) OR import_state @> ?", Channel::Waha::IMPORT_ACTIVE_STATES, { media_pending: true }.to_json)
                 .find_each(&:reconcile_import!)
  end
end
