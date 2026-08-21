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
  json.partial!(
    'api/v1/accounts/kanban_boards/stage_pagination',
    formats: [:json],
    result: @result,
    limit: @limit
  )
end
