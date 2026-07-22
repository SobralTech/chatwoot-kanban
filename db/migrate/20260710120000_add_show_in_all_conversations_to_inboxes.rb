class AddShowInAllConversationsToInboxes < ActiveRecord::Migration[7.1]
  def change
    add_column :inboxes, :show_in_all_conversations, :boolean, default: true, null: false
    add_index :inboxes, [:account_id, :show_in_all_conversations]
  end
end
