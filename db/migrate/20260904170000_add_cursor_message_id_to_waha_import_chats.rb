class AddCursorMessageIdToWahaImportChats < ActiveRecord::Migration[7.1]
  def change
    add_column :waha_import_chats, :cursor_message_id, :string
  end
end
