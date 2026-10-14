require 'rails_helper'

describe Waha::SessionService do
  let(:channel) { create(:channel_waha) }
  let(:service) { described_class.new(channel: channel) }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }

  it 'subscribes every WAHA session to the separate GOWS poll vote event' do
    expect(described_class::WEBHOOK_EVENTS).to include('poll.vote')
  end

  it 'subscribes to the call events the webhook job handles' do
    expect(described_class::WEBHOOK_EVENTS).to include('call.received', 'call.accepted', 'call.rejected')
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

  describe '#sync_webhook_config' do
    let(:session_url) { "https://waha.test/api/sessions/#{channel.session_name}" }
    let!(:update_request) { stub_request(:put, session_url).to_return(status: 200, body: '{}', headers: json_headers) }

    it 'keeps the rest of the session config when replacing a drifted webhook' do
      other_webhook = { 'url' => 'https://n8n.test/hook', 'events' => ['message'] }
      session_info = {
        'config' => {
          'proxy' => { 'server' => 'proxy.test:3128' },
          'webhooks' => [other_webhook, { 'url' => channel.webhook_url, 'events' => ['message.any'] }]
        }
      }

      service.sync_webhook_config(session_info)

      expected_config = {
        'proxy' => { 'server' => 'proxy.test:3128' },
        'webhooks' => [other_webhook, { 'url' => channel.webhook_url, 'events' => described_class::WEBHOOK_EVENTS }]
      }
      expect(update_request.with(body: { config: expected_config }.to_json)).to have_been_requested
    end

    it 'does nothing when the webhook is already current' do
      webhook = { 'url' => channel.webhook_url, 'events' => described_class::WEBHOOK_EVENTS }

      service.sync_webhook_config({ 'config' => { 'webhooks' => [webhook] } })

      expect(update_request).not_to have_been_requested
    end

    it 'does nothing when the session could not be fetched' do
      service.sync_webhook_config(nil)

      expect(update_request).not_to have_been_requested
    end
  end
end
