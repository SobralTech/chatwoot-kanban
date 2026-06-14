class CreateConversationAssistantMessages < ActiveRecord::Migration[7.1]
  def change
    create_table :conversation_assistant_messages do |t|
      t.references :account, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :question, null: false
      t.text :suggested_reply
      t.text :internal_note
      t.jsonb :sources, null: false, default: []
      t.string :model
      t.boolean :web_search_used, null: false, default: false
      t.jsonb :usage, null: false, default: {}
      t.integer :status, null: false, default: 0
      t.datetime :sent_to_customer_at
      t.references :sent_message, foreign_key: { to_table: :messages }

      t.timestamps
    end

    add_index :conversation_assistant_messages,
              [:account_id, :conversation_id, :user_id, :created_at],
              name: 'idx_conversation_assistant_messages_memory'
  end
end
