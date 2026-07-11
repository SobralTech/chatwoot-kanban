class CreateConversationAccessUsers < ActiveRecord::Migration[7.0]
  def change
    create_table :conversation_access_users do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.references :conversation, null: false, foreign_key: true, index: false
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end

    add_index :conversation_access_users, [:conversation_id, :user_id], unique: true, name: 'idx_conversation_access_users_unique'
    add_index :conversation_access_users, [:user_id, :conversation_id], name: 'idx_conversation_access_users_user_conversation'
    add_index :conversation_access_users, [:account_id, :user_id], name: 'idx_conversation_access_users_account_user'
  end
end
