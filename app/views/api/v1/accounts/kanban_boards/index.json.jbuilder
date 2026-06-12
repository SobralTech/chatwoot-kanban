json.array! @kanban_boards do |kanban_board|
  json.partial! 'api/v1/accounts/kanban_boards/kanban_board', formats: [:json], kanban_board: kanban_board
  json.visibility_mode kanban_board.visibility_mode
  json.inbox_scope_mode kanban_board.inbox_scope_mode
  json.cards_count @overview_cards_count_by_board_id.fetch(kanban_board.id, 0)

  json.stages_summary do
    json.array! @overview_stages_by_board_id.fetch(kanban_board.id, []) do |kanban_stage|
      json.id kanban_stage.id
      json.name kanban_stage.name
      json.color kanban_stage.color
      json.cards_count @overview_cards_count_by_stage_id.fetch(kanban_stage.id, 0)
    end
  end

  json.visible_users do
    json.array! @overview_visible_users_by_board_id.fetch(kanban_board.id, []) do |user|
      json.id user.id
      json.name user.name
      json.avatar_url user.avatar_url
    end
  end

  json.allowed_inboxes do
    json.array! @overview_allowed_inboxes_by_board_id.fetch(kanban_board.id, []) do |inbox|
      json.id inbox.id
      json.name inbox.name
      json.channel_type inbox.channel_type
    end
  end
end
