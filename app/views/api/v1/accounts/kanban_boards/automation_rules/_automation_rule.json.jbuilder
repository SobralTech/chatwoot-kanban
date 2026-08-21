json.id automation_rule.id
json.account_id automation_rule.account_id
json.kanban_board_id automation_rule.kanban_board_id
json.name automation_rule.name
json.description automation_rule.description
json.event_name automation_rule.event_name
json.conditions automation_rule.conditions
json.actions automation_rule.actions
json.position automation_rule.position
json.active automation_rule.active?
json.dry_run automation_rule.dry_run?
json.stop_after_match automation_rule.stop_after_match?
json.created_by_id automation_rule.created_by_id
json.created_on automation_rule.created_at.to_i
json.executions_count automation_rule.kanban_automation_logs.where('created_at >= ?', 7.days.ago).count
