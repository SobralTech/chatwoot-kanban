json.partial! 'api/v1/accounts/kanban_boards/card', formats: [:json], card: @kanban_card, conversation_kanban_state: nil
json.due_at @kanban_card.due_at&.iso8601
