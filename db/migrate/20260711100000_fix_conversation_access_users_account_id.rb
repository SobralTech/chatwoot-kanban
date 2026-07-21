class FixConversationAccessUsersAccountId < ActiveRecord::Migration[7.0]
  def up
    return if column_exists?(:conversation_access_users, :account_id)

    # The original create_conversation_access_users migration was edited after it
    # had already run on some environments, so their tables never got this column
    # even though schema_migrations marks it as applied. Backfilling here instead
    # of relying on the (already-run) create migration.
    add_reference :conversation_access_users, :account, null: true, foreign_key: true, index: false
    execute <<-SQL.squish
      UPDATE conversation_access_users
      SET account_id = conversations.account_id
      FROM conversations
      WHERE conversations.id = conversation_access_users.conversation_id
    SQL
    change_column_null :conversation_access_users, :account_id, false
    add_index :conversation_access_users, [:account_id, :user_id], name: 'idx_conversation_access_users_account_user'
  end

  # account_id is part of the canonical table definition and may predate this repair migration.
  def down; end
end
