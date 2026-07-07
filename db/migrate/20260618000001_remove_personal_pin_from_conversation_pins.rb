class RemovePersonalPinFromConversationPins < ActiveRecord::Migration[7.1]
  def up
    remove_index :conversation_pins, name: 'idx_conv_pins_personal_unique'
    remove_index :conversation_pins, name: 'idx_conv_pins_account_unique'
    remove_column :conversation_pins, :pin_type

    add_index :conversation_pins, :conversation_id, unique: true, name: 'idx_conv_pins_unique'
  end

  def down
    remove_index :conversation_pins, name: 'idx_conv_pins_unique'
    add_column :conversation_pins, :pin_type, :integer, default: 0, null: false

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
