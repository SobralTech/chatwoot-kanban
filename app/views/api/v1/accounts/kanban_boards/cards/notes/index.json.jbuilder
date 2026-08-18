json.payload @notes do |note|
  json.partial! 'api/v1/accounts/kanban_boards/cards/notes/note', formats: [:json], note: note
end
json.has_more @has_more
json.next_cursor @next_cursor
