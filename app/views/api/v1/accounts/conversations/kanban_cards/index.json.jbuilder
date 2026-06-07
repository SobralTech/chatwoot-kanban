json.payload do
  json.array! @kanban_cards do |kanban_card|
    json.partial! 'api/v1/accounts/conversations/kanban_cards/kanban_card', formats: [:json], kanban_card: kanban_card
  end
end
