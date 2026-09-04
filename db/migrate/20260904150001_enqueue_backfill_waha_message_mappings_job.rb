class EnqueueBackfillWahaMessageMappingsJob < ActiveRecord::Migration[7.1]
  def up
    Migration::BackfillWahaMessageMappingsJob.perform_later
  end

  def down; end
end
