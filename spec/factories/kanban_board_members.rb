FactoryBot.define do
  factory :kanban_board_member do
    account
    kanban_board { association :kanban_board, account: account }
    user { association :user, account: account }
  end
end
