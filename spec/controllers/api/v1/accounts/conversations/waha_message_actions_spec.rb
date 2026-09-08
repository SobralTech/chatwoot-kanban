require 'rails_helper'

RSpec.describe 'WAHA canonical message actions', type: :request do
  let(:channel) { create(:channel_waha) }
  let(:inbox) { channel.inbox }
  let(:account) { channel.account }
  let(:agent) { create(:user, account: account, role: :administrator) }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, source_id: '5511888888888@c.us', contact: create(:contact, account: account)) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact_inbox.contact, contact_inbox: contact_inbox) }
  let(:message) do
    create_waha_message(conversation: conversation, inbox: inbox, account: account, message_type: :outgoing,
                        source_id: 'true_5511888888888@c.us_CANONICAL')
  end
  let(:path) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages" }
  let(:provider_path) { "https://waha.test/api/#{channel.session_name}/chats/5511888888888@c.us/messages/true_5511888888888@c.us_CANONICAL" }

  it 'presents canonical source_id in the API and broadcasts while leaving the database column empty' do
    message
    get path, headers: agent.create_new_auth_token

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['payload'].find { |item| item['id'] == message.id }['source_id']).to eq(message.presented_source_id)
    expect(message.push_event_data[:source_id]).to eq(message.presented_source_id)
    expect(message.webhook_data[:source_id]).to eq(message.presented_source_id)
    expect(message.source_id).to be_nil
  end

  it 'edits a canonically mapped message through the provider' do
    stub_request(:put, provider_path).to_return(status: 200, body: '{}')

    post "#{path}/#{message.id}/waha_edit", params: { content: 'Updated' }, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(WebMock).to have_requested(:put, provider_path)
  end

  it 'reacts to a canonically mapped message through the provider' do
    stub_request(:put, 'https://waha.test/api/reaction').to_return(status: 200, body: '{}')

    post "#{path}/#{message.id}/waha_react", params: { emoji: '👍' }, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(WebMock).to have_requested(:put, 'https://waha.test/api/reaction')
      .with(body: hash_including('messageId' => message.presented_source_id))
  end

  it 'revokes through the provider and retains the canonical identity after local deletion' do
    stub_request(:delete, provider_path).to_return(status: 200, body: '{}')

    delete "#{path}/#{message.id}", headers: agent.create_new_auth_token

    expect(response).to have_http_status(:success)
    expect(WebMock).to have_requested(:delete, provider_path)
    expect(message.reload.content_attributes['deleted']).to be(true)
    expect(Waha::Anchoring.find_message(channel, message.presented_source_id)).to eq(message)
  end
end
