FactoryBot.define do
  factory :kanban_automation_rule do
    account
    kanban_board { association(:kanban_board, account: account) }
    sequence(:name) { |n| "Automation Rule #{n}" }
    event_name { 'card_created' }
    conditions { [] }
    actions do
      [
        {
          'action_name' => 'set_priority',
          'action_params' => { 'priority' => 'high' }
        }
      ]
    end
    position { 0 }
    active { false }
    dry_run { true }
    stop_after_match { false }
  end
end
