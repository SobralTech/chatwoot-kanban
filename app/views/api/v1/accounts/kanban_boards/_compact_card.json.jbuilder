json.id card.id
json.kanban_stage_id card.kanban_stage_id
json.position card.position
json.origin card.origin
json.subject card.subject
json.active card.active
json.contact do
  json.partial! 'api/v1/models/contact', formats: [:json], resource: card.contact
end
json.inbox do
  json.partial! 'api/v1/models/inbox_slim', formats: [:json], resource: card.inbox
end
json.conversation_id card.conversation&.display_id
json.moved_by_id nil
json.moved_at nil
