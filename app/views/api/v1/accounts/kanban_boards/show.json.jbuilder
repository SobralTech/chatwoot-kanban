json.partial! 'api/v1/accounts/kanban_boards/kanban_board', formats: [:json], kanban_board: @kanban_board
json.inbox_scope_mode @kanban_board.inbox_scope_mode
json.allowed_inbox_ids @kanban_board.kanban_board_inboxes.order(:inbox_id).pluck(:inbox_id)
json.assignable_users @kanban_board.assignable_users.order(:name) do |user|
  json.id user.id
  json.name user.name
  json.avatar_url user.avatar_url
end

json.stages do
  json.array! @kanban_stages do |kanban_stage|
    json.partial! 'api/v1/accounts/kanban_boards/stage', formats: [:json], kanban_stage: kanban_stage

    stage_card_result = @stage_card_results.fetch(kanban_stage)
    json.total_value stage_card_result.total_value
    json.cards do
      json.array! stage_card_result.cards do |card|
        json.partial!(
          'api/v1/accounts/kanban_boards/compact_card',
          formats: [:json],
          card: card
        )
      end
    end

    json.pagination do
      json.limit @stage_card_limit
      json.has_more stage_card_result.has_more
      json.next_cursor stage_card_result.next_cursor
      json.total_count stage_card_result.total_count
      json.total_value stage_card_result.total_value
    end
  end
end
