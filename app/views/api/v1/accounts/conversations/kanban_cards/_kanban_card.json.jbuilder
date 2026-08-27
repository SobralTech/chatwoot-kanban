include_metadata ||= false

json.id kanban_card.id
json.origin kanban_card.origin
json.subject kanban_card.display_subject
if include_metadata
  json.due_at kanban_card.due_at&.iso8601
  json.priority kanban_card.priority
  json.value KanbanCards::Totals.decimal_string(kanban_card.total_value)
  json.kanban_reason_id kanban_card.kanban_reason_id
  json.custom_field_keys(kanban_card.kanban_card_field_values.map { |field_value| field_value.kanban_custom_field.key })
  json.stage_entered_at kanban_card.stage_entered_at&.iso8601
  json.labels(kanban_card.labels.map(&:name).filter_map { |title| labels_by_title[title] }) do |label|
    json.extract! label, :id, :title, :color, :description
  end
  json.assignees kanban_card.assignees do |user|
    json.id user.id
    json.name user.name
    json.avatar_url user.avatar_url
  end
end
json.kanban_board do
  json.id kanban_card.kanban_board_id
  json.name kanban_card.kanban_board.name
end
json.kanban_stage do
  json.id kanban_card.kanban_stage_id
  json.name kanban_card.kanban_stage.name
  json.color kanban_card.kanban_stage.color
  json.sla_hours kanban_card.kanban_stage.sla_hours
end
json.conversation_id kanban_card.conversation.display_id
