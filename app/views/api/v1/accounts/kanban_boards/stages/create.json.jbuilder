json.partial! 'api/v1/accounts/kanban_boards/stage', formats: [:json], kanban_stage: @kanban_stage
json.total_value @kanban_stage.total_value
