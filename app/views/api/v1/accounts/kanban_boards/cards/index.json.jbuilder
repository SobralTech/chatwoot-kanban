json.cards do
  json.array! @result.cards do |card|
    json.partial!(
      'api/v1/accounts/kanban_boards/card',
      formats: [:json],
      card: card,
      stable_card: true
    )
  end
end

json.pagination do
  json.limit @limit
  json.has_more @result.has_more
  json.next_cursor @result.next_cursor
  json.total_count @result.total_count
end
