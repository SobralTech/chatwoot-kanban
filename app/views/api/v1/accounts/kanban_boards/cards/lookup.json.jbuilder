json.array! @kanban_cards do |card|
  json.stage_name card.kanban_stage.name
  json.conversation_id card.conversation&.display_id
  json.terminal @terminal_stage_ids.include?(card.kanban_stage_id)
end
