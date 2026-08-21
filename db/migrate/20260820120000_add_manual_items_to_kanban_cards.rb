class AddManualItemsToKanbanCards < ActiveRecord::Migration[7.1]
  def change
    add_column :kanban_card_products, :item_type, :integer, null: false, default: 0
    change_column_null :kanban_card_products, :sku, true
    add_column :kanban_cards, :discount_type, :integer, null: false, default: 0
    add_column :kanban_cards, :discount_amount, :decimal, precision: 12, scale: 2
  end
end
