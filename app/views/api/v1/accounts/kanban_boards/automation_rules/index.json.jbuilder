json.payload @automation_rules do |automation_rule|
  json.partial! 'api/v1/accounts/kanban_boards/automation_rules/automation_rule',
                formats: [:json], automation_rule: automation_rule,
                executions_count: @automation_execution_counts.fetch(automation_rule.id, 0)
end
