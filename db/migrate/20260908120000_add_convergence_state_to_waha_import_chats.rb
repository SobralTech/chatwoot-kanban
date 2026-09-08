class AddConvergenceStateToWahaImportChats < ActiveRecord::Migration[7.1]
  def change
    add_column :waha_import_chats, :execution_id, :string
    add_column :waha_import_chats, :pass_id, :string
    add_column :waha_import_chats, :pass_number, :integer, null: false, default: 1
    add_column :waha_import_chats, :discovered_pass, :integer, null: false, default: 1
    add_column :waha_import_chats, :attempts, :integer, null: false, default: 0
    add_column :waha_import_chats, :next_attempt_at, :datetime
    add_column :waha_import_chats, :lease_token, :string
    add_column :waha_import_chats, :lease_expires_at, :datetime
    add_column :waha_import_chats, :pass_imported_count, :integer, null: false, default: 0
    add_column :waha_import_chats, :observed_message_count, :integer, null: false, default: 0
    add_column :waha_import_chats, :observed_message_digest, :string
    add_column :waha_import_chats, :pass_observed_message_count, :integer, null: false, default: 0
    add_column :waha_import_chats, :pass_observed_message_digest, :string

    add_index :waha_import_chats, %i[channel_waha_id execution_id pass_id status],
              name: 'index_waha_import_chats_on_pass_claim'
    add_index :waha_import_chats, :lease_expires_at
  end
end
