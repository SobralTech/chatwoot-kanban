include_metadata ||= false

json.id kanban_card.id
json.origin kanban_card.origin
json.subject kanban_card.subject.presence || "#{kanban_card.contact.name.presence || "Contact ##{kanban_card.contact_id}"} - #{kanban_card.inbox.name.presence || "Inbox ##{kanban_card.inbox_id}"}"
if include_metadata
  json.due_at kanban_card.due_at&.iso8601
  json.priority kanban_card.priority
  json.labels kanban_card.labels.map(&:name).filter_map { |title| labels_by_title[title] } do |label|
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
end
json.conversation_id kanban_card.conversation.display_id
