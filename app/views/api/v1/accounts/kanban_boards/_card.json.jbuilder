json.id conversation_kanban_state.id
json.account_id conversation_kanban_state.account_id
json.kanban_board_id conversation_kanban_state.kanban_board_id
json.kanban_stage_id conversation_kanban_state.kanban_stage_id
json.conversation_id conversation_kanban_state.conversation.display_id
json.position conversation_kanban_state.position
json.moved_by_id conversation_kanban_state.moved_by_id
json.moved_at conversation_kanban_state.moved_at&.to_i
json.created_at conversation_kanban_state.created_at.to_i
json.updated_at conversation_kanban_state.updated_at.to_i
json.conversation do
  json.partial! 'api/v1/conversations/partials/conversation', formats: [:json],
                conversation: conversation_kanban_state.conversation
end
