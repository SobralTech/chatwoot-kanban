json.payload @automation_logs do |log|
  json.id log.id
  json.account_id log.account_id
  json.kanban_automation_rule_id log.kanban_automation_rule_id
  json.kanban_card_id log.kanban_card_id
  json.event_name log.event_name
  json.status log.status
  json.details log.details
  json.created_at log.created_at.to_i
end
