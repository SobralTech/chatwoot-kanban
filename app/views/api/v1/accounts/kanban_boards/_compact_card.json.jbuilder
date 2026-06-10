conversation = card.conversation
assignee = conversation&.assignee

json.id card.id
json.kanban_stage_id card.kanban_stage_id
json.position card.position
json.origin card.origin
json.subject card.subject
json.active card.active
json.due_at card.due_at&.iso8601
json.stage_entered_at card.stage_entered_at&.iso8601
json.contact do
  json.partial! 'api/v1/models/contact', formats: [:json], resource: card.contact
end
json.inbox do
  json.partial! 'api/v1/models/inbox_slim', formats: [:json], resource: card.inbox
end
json.conversation_id conversation&.display_id
json.priority conversation&.priority
json.conversation do
  if conversation
    json.id conversation.id
    json.display_id conversation.display_id
  else
    json.nil!
  end
end
json.assignee do
  if assignee
    json.id assignee.id
    json.name assignee.name
    json.avatar_url assignee.avatar_url
  else
    json.nil!
  end
end
json.moved_by_id nil
json.moved_at nil
