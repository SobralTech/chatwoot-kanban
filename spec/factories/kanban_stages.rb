FactoryBot.define do
  factory :kanban_stage do
    account
    kanban_board { association(:kanban_board, account: account) }
    sequence(:name) { |n| "Stage #{n}" }
    color { '#8B8D98' }
    position { 0 }
    active { true }
  end
end
