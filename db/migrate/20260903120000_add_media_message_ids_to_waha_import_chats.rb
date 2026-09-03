class AddMediaMessageIdsToWahaImportChats < ActiveRecord::Migration[7.1]
  def change
    add_column :waha_import_chats, :media_message_ids, :bigint, array: true, default: [], null: false
  end
end
