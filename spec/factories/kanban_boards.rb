FactoryBot.define do
  factory :kanban_board do
    sequence(:name) { |n| "Kanban Board #{n}" }
    description { 'Sales funnel' }
    position { 0 }
    active { true }
    account
  end
end
