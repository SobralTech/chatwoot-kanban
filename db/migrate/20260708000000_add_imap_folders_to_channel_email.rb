class AddImapFoldersToChannelEmail < ActiveRecord::Migration[7.1]
  def change
    add_column :channel_email, :imap_folders, :text, array: true, default: []
  end
end
