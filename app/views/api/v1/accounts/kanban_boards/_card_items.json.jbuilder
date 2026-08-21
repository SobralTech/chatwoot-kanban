json.products card.kanban_card_products.ordered do |product|
  json.partial! 'api/v1/accounts/kanban_boards/card_product', formats: [:json], product: product
end
json.items_total card.items_total
json.discount_type card.discount_type
json.discount_amount card.discount_amount
json.discount_value card.discount_value
json.value card.total_value
