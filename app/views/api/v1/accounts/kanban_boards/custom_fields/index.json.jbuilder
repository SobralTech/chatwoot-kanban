json.array! @kanban_custom_fields do |custom_field|
  json.partial! 'api/v1/accounts/kanban_boards/custom_field', formats: [:json], custom_field: custom_field
end
