json.stage_id @kanban_stage.id

json.cards do
  json.array! @result.cards do |card|
    json.partial!(
      'api/v1/accounts/kanban_boards/compact_card',
      formats: [:json],
      card: card
    )
  end
end

json.pagination do
  json.limit @limit
  json.has_more @result.has_more
  json.next_cursor @result.next_cursor
  json.total_count @result.total_count
end
