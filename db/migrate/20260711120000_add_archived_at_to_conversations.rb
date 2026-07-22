class AddArchivedAtToConversations < ActiveRecord::Migration[7.0]
  def change
    add_column :conversations, :archived_at, :datetime
    add_index :conversations, [:account_id, :archived_at]
  end
end
