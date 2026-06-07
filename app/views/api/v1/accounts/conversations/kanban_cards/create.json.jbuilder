json.payload do
  json.partial! 'api/v1/accounts/conversations/kanban_cards/kanban_card', formats: [:json], kanban_card: @kanban_card
end
