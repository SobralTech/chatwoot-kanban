json.partial! 'api/v1/accounts/kanban_boards/kanban_board', formats: [:json], kanban_board: @kanban_board
json.inbox_scope_mode @kanban_board.derived_inbox_scope_mode
json.allowed_inbox_ids @kanban_board.derived_allowed_inbox_ids
json.assignable_users @kanban_board.assignable_users.order(:name) do |user|
  json.id user.id
  json.name user.name
  json.avatar_url user.avatar_url
end

json.stages do
  json.array! @kanban_stages do |kanban_stage|
    json.partial! 'api/v1/accounts/kanban_boards/stage', formats: [:json], kanban_stage: kanban_stage

    stage_card_result = @stage_card_results.fetch(kanban_stage)
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
      json.partial!(
        'api/v1/accounts/kanban_boards/stage_pagination',
        formats: [:json],
        result: stage_card_result,
        limit: @stage_card_limit
      )
    end
  end
end
