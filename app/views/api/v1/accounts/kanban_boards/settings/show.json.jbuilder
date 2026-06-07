json.id @kanban_board.id
json.name @kanban_board.name
json.description @kanban_board.description
json.visibility_mode @kanban_board.visibility_mode
json.visible_user_ids @kanban_board.kanban_board_members.order(:user_id).pluck(:user_id)
json.inbox_scope_mode @kanban_board.inbox_scope_mode
json.allowed_inbox_ids @kanban_board.kanban_board_inboxes.order(:inbox_id).pluck(:inbox_id)
json.auto_create_cards_from_conversations @kanban_board.auto_create_cards_from_conversations
