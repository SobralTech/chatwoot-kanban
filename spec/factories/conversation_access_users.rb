FactoryBot.define do
  factory :conversation_access_user do
    account { conversation.account }
    conversation
    user
  end
end
