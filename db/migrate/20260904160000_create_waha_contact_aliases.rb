class CreateWahaContactAliases < ActiveRecord::Migration[7.1]
  def change
    create_table :waha_contact_aliases do |t|
      t.references :channel_waha, null: false, foreign_key: { to_table: :channel_waha, on_delete: :cascade }
      t.references :contact_inbox, null: false, foreign_key: { on_delete: :cascade }
      t.string :alias_type, null: false
      t.string :value, null: false

      t.timestamps
    end

    add_index :waha_contact_aliases, %i[channel_waha_id alias_type value],
              unique: true, name: 'index_waha_contact_aliases_on_identity'
  end
end
