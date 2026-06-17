class CreateConversationPins < ActiveRecord::Migration[7.1]
  def change
    create_table :conversation_pins do |t|
      t.references :account, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :pin_type, default: 0, null: false
      t.datetime :pinned_at, null: false

      t.timestamps
    end

    add_index :conversation_pins, [:conversation_id, :user_id],
              unique: true,
              where: 'pin_type = 0',
              name: 'idx_conv_pins_personal_unique'

    add_index :conversation_pins, [:conversation_id, :account_id],
              unique: true,
              where: 'pin_type = 1',
              name: 'idx_conv_pins_account_unique'
  end
end
