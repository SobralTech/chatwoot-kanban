class AddKanbanSearchIndexes < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    execute <<~SQL.squish
      CREATE OR REPLACE FUNCTION immutable_unaccent(text)
      RETURNS text AS $$ SELECT unaccent('unaccent', $1) $$
      LANGUAGE sql IMMUTABLE PARALLEL SAFE STRICT;
    SQL

    add_index :kanban_cards, 'immutable_unaccent(lower(subject)) gin_trgm_ops',
              using: :gin, name: 'index_kanban_cards_on_subject_trgm',
              where: 'active = true', algorithm: :concurrently

    add_index :contacts, 'immutable_unaccent(lower(name)) gin_trgm_ops',
              using: :gin, name: 'index_contacts_on_name_trgm', algorithm: :concurrently

    add_index :contacts, 'lower(email) gin_trgm_ops',
              using: :gin, name: 'index_contacts_on_email_trgm', algorithm: :concurrently

    add_index :contacts, "regexp_replace(phone_number, '\\D', '', 'g') gin_trgm_ops",
              using: :gin, name: 'index_contacts_on_phone_digits_trgm', algorithm: :concurrently
  end

  def down
    remove_index :kanban_cards, name: 'index_kanban_cards_on_subject_trgm', algorithm: :concurrently
    remove_index :contacts, name: 'index_contacts_on_name_trgm', algorithm: :concurrently
    remove_index :contacts, name: 'index_contacts_on_email_trgm', algorithm: :concurrently
    remove_index :contacts, name: 'index_contacts_on_phone_digits_trgm', algorithm: :concurrently
    execute 'DROP FUNCTION IF EXISTS immutable_unaccent(text);'
  end
end
