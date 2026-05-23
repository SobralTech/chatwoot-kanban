json.array! @kanban_boards do |kanban_board|
  json.partial! 'api/v1/accounts/kanban_boards/kanban_board', formats: [:json], kanban_board: kanban_board
end
