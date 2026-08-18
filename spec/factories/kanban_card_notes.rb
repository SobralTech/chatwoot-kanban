FactoryBot.define do
  factory :kanban_card_note do
    account
    kanban_card { association(:kanban_card, account: account) }
    user { nil }
    content { 'Customer requested a follow-up.' }
  end
end
