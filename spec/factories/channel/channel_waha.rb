FactoryBot.define do
  factory :channel_waha, class: 'Channel::Waha' do
    account
    waha_url { 'https://waha.test' }
    api_key { 'test-api-key' }
    sequence(:session_name) { |n| "session_#{n}" }

    before(:create) do |channel|
      channel.define_singleton_method(:start_waha_session) { nil }
    end

    after(:create) do |channel|
      create(:inbox, channel: channel, account: channel.account)
    end
  end
end
