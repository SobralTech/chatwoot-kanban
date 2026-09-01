class AddSourceStanzaIndexToMessages < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  # Two WAHA lookups ran as unindexable predicates over the whole inbox, on every
  # inbound webhook event:
  #
  #   source_id LIKE '%_<stanza>'          (message identity; leading wildcard)
  #   additional_attributes->>'edit_of'    (edit-family anchor; json extraction)
  #
  # Both now have an index matching the expression they compare against.
  def change
    add_index :messages,
              "inbox_id, (regexp_replace(source_id, '^.*_', ''))",
              name: 'index_messages_on_inbox_and_source_stanza',
              where: 'source_id IS NOT NULL',
              algorithm: :concurrently

    add_index :messages,
              "inbox_id, ((additional_attributes->>'edit_of'))",
              name: 'index_messages_on_inbox_and_edit_of',
              where: "additional_attributes->>'edit_of' IS NOT NULL",
              algorithm: :concurrently
  end
end
