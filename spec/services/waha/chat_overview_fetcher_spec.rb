require 'rails_helper'

describe Waha::ChatOverviewFetcher do
  let(:channel) { create(:channel_waha, groups_enabled: true) }
  let(:since) { Time.zone.parse('2026-10-14T12:00:00Z') }
  let(:overview) do
    [
      { 'id' => 'old@c.us', 'lastMessage' => { 'timestamp' => since.to_i - 1 } },
      { 'id' => 'recent@c.us', 'lastMessage' => { 'timestamp' => since.to_i } },
      { 'id' => 'empty@c.us', 'lastMessage' => nil },
      { 'id' => '120363000000000000@g.us', 'lastMessage' => { 'timestamp' => since.to_i + 60 } },
      { 'id' => 'status@broadcast', 'lastMessage' => { 'timestamp' => since.to_i + 60 } }
    ]
  end

  before do
    stub_request(:get, %r{https://waha\.test/api/#{channel.session_name}/chats/overview})
      .to_return(status: 200, body: overview.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  it 'skips in-scope chats whose last message predates the window' do
    expect(described_class.new(channel: channel, since: since).all)
      .to eq(['120363000000000000@g.us', 'recent@c.us', 'empty@c.us'])
  end

  it 'keeps every in-scope chat without a window start' do
    expect(described_class.new(channel: channel).all)
      .to eq(['120363000000000000@g.us', 'old@c.us', 'recent@c.us', 'empty@c.us'])
  end
end
