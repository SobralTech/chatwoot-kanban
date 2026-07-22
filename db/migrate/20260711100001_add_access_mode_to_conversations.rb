class AddAccessModeToConversations < ActiveRecord::Migration[7.0]
  def change
    add_column :conversations, :access_mode, :integer, null: false, default: 0
  end
end
