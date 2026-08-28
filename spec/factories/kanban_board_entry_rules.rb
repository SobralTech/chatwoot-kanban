FactoryBot.define do
  factory :kanban_board_entry_rule do
    account
    kanban_board { association :kanban_board, account: account }
    sequence(:name) { |n| "Entry rule #{n}" }
    active { true }
    all_inboxes { true }
    position { 1 }
    conditions { [] }

    trait :selected_inboxes do
      all_inboxes { false }
    end
  end

  factory :kanban_board_entry_rule_inbox do
    account
    kanban_board_entry_rule { association :kanban_board_entry_rule, account: account }
    kanban_board { kanban_board_entry_rule.kanban_board }
    inbox { association :inbox, account: account }
  end
end
