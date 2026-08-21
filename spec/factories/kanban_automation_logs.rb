FactoryBot.define do
  factory :kanban_automation_log do
    account
    kanban_automation_rule { association(:kanban_automation_rule, account: account) }
    kanban_card { nil }
    event_name { 'card_created' }
    status { 'executed' }
    details { {} }
  end
end
