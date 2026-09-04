class CreateWahaMessageMappings < ActiveRecord::Migration[7.1]
  def change
    create_table :waha_message_mappings do |t|
      t.references :channel_waha, null: false, foreign_key: { to_table: :channel_waha }
      t.references :message, null: false, foreign_key: true
      t.string :chat_jid, null: false
      t.string :external_id, null: false
      t.string :participant_jid
      t.integer :direction, null: false
      t.integer :event_type, null: false, default: 0
      t.integer :part, null: false, default: 0

      t.timestamps
    end

    # The canonical identity: one real WhatsApp event, once, per chat. Scoping by
    # chat_jid (not just channel) matters because a WAHA stanza id is unique only
    # within the chat that produced it, not across the whole session — the same
    # legacy ambiguity Waha::Anchoring.by_stanza carries by only scoping to inbox.
    # event_type is included because some engines reuse the original message's id
    # for its edit event; GOWS does not, but the constraint stays correct either way.
    add_index :waha_message_mappings, %i[channel_waha_id chat_jid external_id event_type],
              unique: true, name: 'index_waha_message_mappings_on_identity'
  end
end
