class CreateKanbanCardProducts < ActiveRecord::Migration[7.1]
  def change
    create_table :kanban_card_products do |t|
      t.references :account, null: false, foreign_key: true
      t.references :kanban_card, null: false, foreign_key: true
      t.string :sku, null: false
      t.string :name, null: false
      t.string :brand
      t.string :image_url
      t.integer :quantity, null: false, default: 1
      t.decimal :unit_price, null: false, precision: 12, scale: 2
      t.integer :price_type, null: false, default: 0
      t.string :price_list
      t.integer :position, null: false, default: 0

      t.timestamps
    end
  end
end
