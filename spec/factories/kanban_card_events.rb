FactoryBot.define do
  factory :kanban_card_event do
    account
    kanban_card { association(:kanban_card, account: account) }
    kanban_board { kanban_card.kanban_board }
    user { nil }
    event_type { 'stage_changed' }
    metadata { {} }
    created_at { Time.current }
  end
end
