class FixSourceStanzaIndexForGroupParticipantSuffix < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  # A group message id carries a trailing `_<participantJid>` segment
  # (`direction_chat_stanza_participant`) that the original expression —
  # everything after the last underscore — returned instead of the real
  # stanza, colliding every participant's messages after their first onto one
  # false "duplicate" and silently dropping the rest. Waha::Anchoring::STANZA_SQL
  # now strips that trailing JID segment first; this index must match it
  # verbatim for the planner to use it.
  def up
    remove_index :messages, name: 'index_messages_on_inbox_and_source_stanza', algorithm: :concurrently

    add_index :messages,
              "inbox_id, (regexp_replace(regexp_replace(source_id, '_[^_]*@[^_]*$', ''), '^.*_', ''))",
              name: 'index_messages_on_inbox_and_source_stanza',
              where: 'source_id IS NOT NULL',
              algorithm: :concurrently
  end

  def down
    remove_index :messages, name: 'index_messages_on_inbox_and_source_stanza', algorithm: :concurrently

    add_index :messages,
              "inbox_id, (regexp_replace(source_id, '^.*_', ''))",
              name: 'index_messages_on_inbox_and_source_stanza',
              where: 'source_id IS NOT NULL',
              algorithm: :concurrently
  end
end
