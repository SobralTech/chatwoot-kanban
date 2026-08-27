# A move only changes where the card sits, so the response carries just that. The full
# card partial renders the whole conversation and every assignable user on the account,
# which is ~50 queries the callers of a drag-and-drop never read.
json.id card.id
json.kanban_board_id card.kanban_board_id
json.kanban_stage_id card.kanban_stage_id
json.previous_stage_id card.previous_stage_id
json.position card.position
json.stage_entered_at card.stage_entered_at&.iso8601
json.kanban_reason_id card.kanban_reason_id
json.active card.active
json.updated_at card.updated_at.to_i
