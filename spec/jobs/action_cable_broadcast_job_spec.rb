require 'rails_helper'

RSpec.describe ActionCableBroadcastJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:revoked_agent) { create(:user, account: account, role: :agent) }
  let(:authorized_agent) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, access_mode: :selected_agents) }
  let(:payload) { conversation.push_event_data.merge(account_id: account.id) }

  before do
    create(:inbox_member, inbox: inbox, user: revoked_agent)
    create(:inbox_member, inbox: inbox, user: authorized_agent)
  end

  it 'revalidates conversation access when the job performs' do
    members = [revoked_agent.pubsub_token, authorized_agent.pubsub_token, admin.pubsub_token]

    create(:conversation_access_user, account: account, conversation: conversation, user: authorized_agent)

    expect(ActionCable.server).not_to receive(:broadcast).with(revoked_agent.pubsub_token, anything)
    expect(ActionCable.server).to receive(:broadcast).with(authorized_agent.pubsub_token, hash_including(event: 'conversation.updated'))
    expect(ActionCable.server).to receive(:broadcast).with(admin.pubsub_token, hash_including(event: 'conversation.updated'))

    described_class.perform_now(members, 'conversation.updated', payload, conversation.id)
  end

  it 'does not deliver a queued complete event to an agent who lost access' do
    members = [revoked_agent.pubsub_token, authorized_agent.pubsub_token, admin.pubsub_token]

    create(:conversation_access_user, account: account, conversation: conversation, user: authorized_agent)

    expect(ActionCable.server).not_to receive(:broadcast).with(revoked_agent.pubsub_token, anything)
    expect(ActionCable.server).to receive(:broadcast).with(authorized_agent.pubsub_token, anything)
    expect(ActionCable.server).to receive(:broadcast).with(admin.pubsub_token, anything)

    described_class.perform_now(members, 'conversation.updated', payload, conversation.id)
  end

  it 'does not deliver subsequent message events to a revoked agent' do
    message = create(:message, account: account, inbox: inbox, conversation: conversation)
    members = [revoked_agent.pubsub_token, authorized_agent.pubsub_token]

    create(:conversation_access_user, account: account, conversation: conversation, user: authorized_agent)

    expect(ActionCable.server).not_to receive(:broadcast).with(revoked_agent.pubsub_token, anything)
    expect(ActionCable.server).to receive(:broadcast).with(authorized_agent.pubsub_token, hash_including(event: 'message.created'))

    described_class.perform_now(members, 'message.created', message.push_event_data.merge(account_id: account.id), conversation.id)
  end
end
