json.array! @kanban_card_products do |product|
  json.partial! 'api/v1/accounts/kanban_boards/card_product', formats: [:json], product: product
end
