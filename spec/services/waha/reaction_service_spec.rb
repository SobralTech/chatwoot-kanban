require 'rails_helper'

describe Waha::ReactionService do
  let(:channel) { create(:channel_waha) }
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: channel.account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5511888888888@c.us') }
  let(:conversation) do
    create(:conversation, account: channel.account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
  end
  let(:user) { create(:user, account: channel.account) }
  let(:message) do
    create(:message, conversation: conversation, inbox: inbox, account: channel.account,
                     message_type: :incoming, source_id: 'false_5511888888888@c.us_AAA111')
  end

  before { Current.user = user }

  after { Current.user = nil }

  it 'stashes the acting agent as pending_reaction_agent_id and dispatches the reaction' do
    stub_request(:put, 'https://waha.test/api/reaction').to_return(status: 200, body: '{}')

    described_class.new(message: message, emoji: '👍').perform

    expect(message.reload.content_attributes['pending_reaction_agent_id']).to eq(user.id)
  end

  it 'clears the marker instead of leaking it when the WAHA request fails' do
    stub_request(:put, 'https://waha.test/api/reaction').to_return(status: 500, body: '{"message":"down"}')

    expect { described_class.new(message: message, emoji: '👍').perform }
      .to raise_error(CustomExceptions::Waha::TransientError)

    expect(message.reload.content_attributes['pending_reaction_agent_id']).to be_nil
  end
end
