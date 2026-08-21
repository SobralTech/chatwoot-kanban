conversation_kanban_state ||= nil
card ||= conversation_kanban_state
stable_card ||= false
last_movement_event = local_assigns[:last_movement_event]

json.id card.id
json.account_id card.account_id
json.kanban_board_id card.kanban_board_id
json.kanban_stage_id card.kanban_stage_id
json.previous_stage_id card.previous_stage_id if card.respond_to?(:previous_stage_id)
json.conversation_id card.conversation&.display_id
json.position card.position
json.moved_by_id last_movement_event&.user_id
json.moved_at last_movement_event&.created_at&.to_i
json.created_at card.created_at.to_i
json.updated_at card.updated_at.to_i
json.stage_entered_at card.stage_entered_at&.iso8601 if card.respond_to?(:stage_entered_at)
json.origin card.origin if card.respond_to?(:origin)
json.subject card.subject if card.respond_to?(:subject)
json.kanban_reason_id card.kanban_reason_id if card.respond_to?(:kanban_reason_id)
if card.respond_to?(:kanban_card_field_values)
  json.custom_field_keys(card.kanban_card_field_values.map do |field_value|
    field_value.kanban_custom_field.key
  end)
end
json.partial!('api/v1/accounts/kanban_boards/card_items', formats: [:json], card: card) if card.respond_to?(:kanban_card_products)
if stable_card
  json.description card.description
  json.starts_at card.starts_at&.iso8601
  json.due_at card.due_at&.iso8601
  json.priority card.priority if card.respond_to?(:priority)
  if card.respond_to?(:assignees)
    json.assignees card.assignees do |assignee_user|
      json.id assignee_user.id
      json.name assignee_user.name
      json.avatar_url assignee_user.avatar_url
    end
  end
  json.labels card.account.labels.where(title: card.label_list) do |label|
    json.extract! label, :id, :title, :color, :description
  end
  json.assignable_users card.kanban_board.assignable_users.order(:name) do |user|
    json.id user.id
    json.name user.name
    json.avatar_url user.avatar_url
  end
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
