class RemovePersonalPinFromConversationPins < ActiveRecord::Migration[7.1]
  def change
    remove_index :conversation_pins, name: 'idx_conv_pins_personal_unique'
    remove_index :conversation_pins, name: 'idx_conv_pins_account_unique'
    remove_column :conversation_pins, :pin_type, :integer, default: 0, null: false

    add_index :conversation_pins, :conversation_id, unique: true, name: 'idx_conv_pins_unique'
  end
end
