FactoryBot.define do
  factory :kanban_card do
    account
    kanban_board { association(:kanban_board, account: account) }
    kanban_stage { association(:kanban_stage, account: account, kanban_board: kanban_board) }
    contact { association(:contact, account: account) }
    inbox { association(:inbox, account: account) }
    conversation { nil }
    subject { 'New opportunity' }
    origin { 'manual' }
    position { 0 }
    active { true }
    description { nil }
    starts_at { nil }
    due_at { nil }

    trait :conversation_origin do
      account { conversation.account }
      origin { 'conversation' }
      conversation
      contact { conversation.contact }
      inbox { conversation.inbox }
      subject { nil }
    end
  end
end
