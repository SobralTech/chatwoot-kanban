FactoryBot.define do
  factory :conversation_kanban_state do
    account
    conversation { association(:conversation, account: account) }
    kanban_board { association(:kanban_board, account: account) }
    kanban_stage { association(:kanban_stage, account: account, kanban_board: kanban_board) }
    position { 0 }
    moved_at { Time.current }
    moved_by { nil }
  end
end
