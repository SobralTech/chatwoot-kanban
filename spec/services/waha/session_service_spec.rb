require 'rails_helper'

describe Waha::SessionService do
  let(:channel) { create(:channel_waha) }
  let(:service) { described_class.new(channel: channel) }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }

  it 'subscribes every WAHA session to the separate GOWS poll vote event' do
    expect(described_class::WEBHOOK_EVENTS).to include('poll.vote')
  end

  describe '#start' do
    let!(:start_request) do
      stub_request(:post, "https://waha.test/api/sessions/#{channel.session_name}/start").to_return(status: 201, body: '{}', headers: json_headers)
    end

    it 'starts a session that already exists on WAHA' do
      stub_request(:post, 'https://waha.test/api/sessions')
        .to_return(status: 422, body: { message: "Session '#{channel.session_name}' already exists. Use PUT to update it." }.to_json,
                   headers: json_headers)

      service.start

      expect(start_request).to have_been_requested
    end

    it 'does not start when creating the session fails for another reason' do
      stub_request(:post, 'https://waha.test/api/sessions')
        .to_return(status: 422, body: { message: 'Session name is required' }.to_json, headers: json_headers)

      service.start

      expect(start_request).not_to have_been_requested
    end
  end
end
