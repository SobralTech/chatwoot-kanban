class AddManualItemsToKanbanCards < ActiveRecord::Migration[7.1]
  def change
    add_column :kanban_card_products, :item_type, :integer, null: false, default: 0
    change_column_null :kanban_card_products, :sku, true
    add_column :kanban_cards, :discount_cents, :integer
    add_column :kanban_cards, :discount_percent, :decimal, precision: 5, scale: 2
  end
end
