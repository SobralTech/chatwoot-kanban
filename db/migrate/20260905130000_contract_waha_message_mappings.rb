class ContractWahaMessageMappings < ActiveRecord::Migration[7.1]
  def up
    add_column :waha_message_mappings, :provider_id, :text
    add_column :waha_message_mappings, :ambiguous, :boolean, default: false, null: false
    add_reference :waha_message_mappings, :anchor_message, foreign_key: { to_table: :messages }
    WahaMessageMapping.reset_column_information
    Migration::BackfillWahaMessageMappingsJob.perform_now
    remove_index :messages, name: :index_messages_on_inbox_and_edit_of, if_exists: true
    remove_index :messages, name: :index_messages_on_inbox_and_source_stanza, if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'New WAHA messages no longer populate legacy correlation; restore a pre-contract snapshot to roll back'
  end
end
