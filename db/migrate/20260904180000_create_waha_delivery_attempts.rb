class CreateWahaDeliveryAttempts < ActiveRecord::Migration[7.1]
  def change
    create_table :waha_delivery_attempts do |t|
      t.references :channel_waha, null: false, foreign_key: { to_table: :channel_waha }
      t.references :message, null: false, foreign_key: true, index: { unique: true }
      t.string :chat_jid, null: false
      t.integer :status, null: false, default: 0
      t.string :client_message_id
      t.string :external_id
      t.integer :attempt_count, null: false, default: 0
      t.datetime :dispatched_at
      t.text :last_error

      t.timestamps
    end

    # A pre-generated id (see Waha::SendOnWahaService) must never be handed to two
    # different messages, and once WAHA confirms an external id it becomes the
    # same kind of canonical identity WahaMessageMapping already enforces.
    add_index :waha_delivery_attempts, %i[channel_waha_id client_message_id],
              unique: true, name: 'index_waha_delivery_attempts_on_client_message_id', where: 'client_message_id IS NOT NULL'
    add_index :waha_delivery_attempts, %i[channel_waha_id external_id],
              unique: true, name: 'index_waha_delivery_attempts_on_external_id', where: 'external_id IS NOT NULL'
  end
end
