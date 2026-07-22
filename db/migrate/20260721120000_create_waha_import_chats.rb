class CreateWahaImportChats < ActiveRecord::Migration[7.1]
  def change
    create_table :waha_import_chats do |t|
      t.references :channel_waha, null: false, foreign_key: { to_table: :channel_waha }
      t.string :chat_id, null: false
      t.integer :status, null: false, default: 0
      t.integer :imported_count, null: false, default: 0
      t.bigint :cursor
      t.string :error

      t.timestamps
    end

    add_index :waha_import_chats, %i[channel_waha_id chat_id], unique: true
    add_index :waha_import_chats, %i[channel_waha_id status]
  end
end
