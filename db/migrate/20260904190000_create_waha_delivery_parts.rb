class CreateWahaDeliveryParts < ActiveRecord::Migration[7.1]
  def change
    create_table :waha_delivery_parts do |t|
      t.references :waha_delivery_attempt, null: false, foreign_key: true
      t.references :attachment, foreign_key: { on_delete: :nullify }
      t.integer :position, null: false
      t.integer :part_type, null: false
      t.integer :status, null: false, default: 0
      t.string :client_message_id
      t.text :source_id
      t.string :external_id
      t.datetime :dispatched_at
      t.datetime :confirmed_at

      t.timestamps
    end

    add_index :waha_delivery_parts, %i[waha_delivery_attempt_id position],
              unique: true, name: 'index_waha_delivery_parts_on_attempt_and_position'
    add_index :waha_delivery_parts, :client_message_id, where: 'client_message_id IS NOT NULL'
  end
end
