conversation_kanban_state ||= nil
card ||= conversation_kanban_state
stable_card ||= false

json.id card.id
json.account_id card.account_id
json.kanban_board_id card.kanban_board_id
json.kanban_stage_id card.kanban_stage_id
json.conversation_id card.conversation&.display_id
json.position card.position
json.moved_by_id nil
json.moved_at nil
json.created_at card.created_at.to_i
json.updated_at card.updated_at.to_i
json.stage_entered_at card.stage_entered_at&.iso8601 if card.respond_to?(:stage_entered_at)
json.origin card.origin if card.respond_to?(:origin)
json.subject card.subject if card.respond_to?(:subject)
if stable_card
  json.description card.description
  json.starts_at card.starts_at&.iso8601
  json.due_at card.due_at&.iso8601
end
json.active card.active if card.respond_to?(:active)
if card.respond_to?(:origin)
  json.contact do
    json.partial! 'api/v1/models/contact', formats: [:json], resource: card.contact
  end
  json.inbox do
    json.partial! 'api/v1/models/inbox_slim', formats: [:json], resource: card.inbox
  end
end
if card.conversation.present?
  json.conversation do
    json.partial!(
      'api/v1/conversations/partials/conversation',
      formats: [:json],
      conversation: card.conversation
    )
  end
else
  json.conversation nil
end
