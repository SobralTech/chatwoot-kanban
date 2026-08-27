conversation = card.conversation
assignee = conversation&.assignee

json.id card.id
json.kanban_stage_id card.kanban_stage_id
json.previous_stage_id card.previous_stage_id
json.position card.position
json.origin card.origin
json.subject card.subject
json.active card.active
json.custom_field_keys(card.kanban_card_field_values.map { |field_value| field_value.kanban_custom_field.key })
json.kanban_reason_id card.kanban_reason_id
json.partial! 'api/v1/accounts/kanban_boards/card_items', formats: [:json], card: card
json.due_at card.due_at&.iso8601
json.labels card.labels.map(&:name)
json.stage_entered_at card.stage_entered_at&.iso8601
json.contact do
  json.partial! 'api/v1/models/contact_slim', formats: [:json], resource: card.contact
end
json.inbox do
  json.partial! 'api/v1/models/inbox_slim', formats: [:json], resource: card.inbox
end
json.conversation_id conversation&.display_id
json.priority conversation&.priority
json.card_priority card.priority
json.assignees card.assignees do |assignee_user|
  json.id assignee_user.id
  json.name assignee_user.name
  json.avatar_url assignee_user.avatar_url
end
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
