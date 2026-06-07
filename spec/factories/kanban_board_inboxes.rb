FactoryBot.define do
  factory :kanban_board_inbox do
    account
    kanban_board { association :kanban_board, account: account }
    inbox { association :inbox, account: account }
  end
end
