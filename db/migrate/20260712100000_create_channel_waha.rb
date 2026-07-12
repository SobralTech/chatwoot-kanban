class CreateChannelWaha < ActiveRecord::Migration[7.1]
  def change
    create_table :channel_waha do |t|
      t.integer :account_id, null: false
      t.string :phone_number
      t.string :waha_url, null: false
      t.string :api_key, null: false
      t.string :session_name, null: false
      t.string :webhook_token, null: false
      t.boolean :groups_enabled, default: false, null: false
      t.boolean :auto_reconnect, default: true, null: false
      t.boolean :auto_read_receipts, default: true, null: false
      t.string :session_status
      t.jsonb :status_history, default: []

      t.timestamps
    end

    add_index :channel_waha, :account_id
    add_index :channel_waha, :webhook_token, unique: true
  end
end
