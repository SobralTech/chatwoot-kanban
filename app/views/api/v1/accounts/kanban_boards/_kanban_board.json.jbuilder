json.id kanban_board.id
json.account_id kanban_board.account_id
json.name kanban_board.name
json.description kanban_board.description
json.position kanban_board.position
json.active kanban_board.active
json.auto_create_cards_from_conversations kanban_board.auto_create_cards_from_conversations
json.won_stage_id kanban_board.won_stage_id
json.lost_stage_id kanban_board.lost_stage_id
json.lost_reason_required kanban_board.lost_reason_required
json.bulk_action_limit KanbanCards::BulkActionRequest::MAX_CARDS
json.custom_fields kanban_board.kanban_custom_fields.active.ordered do |field|
  json.id field.id
  json.key field.key
  json.field_type field.field_type
  json.multiple field.multiple
  json.position field.position
end
json.reasons kanban_board.kanban_reasons.active.ordered do |reason|
  json.id reason.id
  json.title reason.title
  json.description reason.description
  json.reason_type reason.reason_type
  json.position reason.position
end
json.created_at kanban_board.created_at.to_i
json.updated_at kanban_board.updated_at.to_i
