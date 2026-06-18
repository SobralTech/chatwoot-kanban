# frozen_string_literal: true

FactoryBot.define do
  factory :conversation_pin do
    pinned_at { Time.current }

    after(:build) do |pin|
      pin.account ||= create(:account)
      pin.conversation ||= create(:conversation, account: pin.account)
      pin.user ||= create(:user, account: pin.account, role: :agent)
    end
  end
end
