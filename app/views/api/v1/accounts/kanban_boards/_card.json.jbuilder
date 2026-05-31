card ||= conversation_kanban_state

json.id card.id
json.account_id card.account_id
json.kanban_board_id card.kanban_board_id
json.kanban_stage_id card.kanban_stage_id
json.conversation_id card.conversation.display_id
json.position card.position
json.moved_by_id conversation_kanban_state&.moved_by_id
json.moved_at conversation_kanban_state&.moved_at&.to_i
json.created_at card.created_at.to_i
json.updated_at card.updated_at.to_i
json.origin card.origin if card.respond_to?(:origin)
json.subject card.subject if card.respond_to?(:subject)
json.active card.active if card.respond_to?(:active)
json.conversation do
  json.partial!(
    'api/v1/conversations/partials/conversation',
    formats: [:json],
    conversation: card.conversation
  )
end
