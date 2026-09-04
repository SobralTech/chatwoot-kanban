require 'rails_helper'

describe Waha::ChatHistoryImporter do
  let(:channel) { create(:channel_waha) }
  let(:inbox) { channel.inbox }
  let(:chat_id) { '5511888888888@c.us' }
  let(:contact) { create(:contact, account: channel.account, name: 'Jane Doe', phone_number: '+5511888888888') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: chat_id) }
  let(:message_time) { 10.minutes.ago.change(usec: 0) }
  let(:window) do
    { 'window_start' => 1.hour.ago.utc.iso8601, 'window_end' => Time.current.utc.iso8601 }
  end
  let(:payload) do
    {
      'id' => 'false_5511888888888@c.us_GAPFILL001',
      'body' => 'Recovered while WAHA was disconnected',
      'from' => chat_id,
      'to' => '5511999999999@c.us',
      'fromMe' => false,
      'timestamp' => message_time.to_i,
      'type' => 'chat',
      'hasMedia' => false,
      '_data' => { 'Info' => { 'Chat' => chat_id, 'PushName' => 'Jane Doe' } }
    }
  end

  before do
    allow(Waha::ContactResolver).to receive(:from_payload)
      .and_return(instance_double(Waha::ContactResolver, perform: contact_inbox))
    stub_request(:get, %r{https://waha\.test/api/#{channel.session_name}/chats/5511888888888@c\.us/messages\?})
      .to_return(status: 200, body: [payload].to_json, headers: { 'Content-Type' => 'application/json' })
  end

  def import_history(kind:, conversation:)
    import_chat = WahaImportChat.create!(channel: channel, chat_id: chat_id)
    described_class.new(
      channel: channel, chat_id: chat_id, window: window, import_chat: import_chat, kind: kind
    ).run
    conversation.reload
  end

  shared_examples 'an active conversation' do |status|
    it "keeps a #{status} conversation unread and in the same state during gap-fill" do
      conversation = create(
        :conversation,
        account: channel.account,
        inbox: inbox,
        contact: contact,
        contact_inbox: contact_inbox,
        status: status,
        agent_last_seen_at: 1.hour.ago,
        assignee_last_seen_at: 1.hour.ago
      )
      conversation.reload
      original_seen_at = conversation.agent_last_seen_at
      original_assignee_seen_at = conversation.assignee_last_seen_at

      import_history(kind: 'gap_fill', conversation: conversation)
      expect(conversation.status).to eq(status.to_s)
      expect(conversation.agent_last_seen_at).to eq(original_seen_at)
      expect(conversation.assignee_last_seen_at).to eq(original_assignee_seen_at)
      expect(conversation.unread_incoming_messages_count).to eq(1)
    end

    it 'persists actionable gap-fill provenance' do
      conversation = create(
        :conversation,
        account: channel.account,
        inbox: inbox,
        contact: contact,
        contact_inbox: contact_inbox,
        status: status
      )

      expect { import_history(kind: 'gap_fill', conversation: conversation) }
        .to have_enqueued_job(SendReplyJob).exactly(:once)

      recovered_message = conversation.messages.find_by!(source_id: payload['id'])
      expect(recovered_message.created_at).to eq(message_time)
      expect(recovered_message.additional_attributes).to include('waha_import_kind' => 'gap_fill')
      expect(recovered_message.additional_attributes).not_to have_key('imported')
    end
  end

  it_behaves_like 'an active conversation', :open
  it_behaves_like 'an active conversation', :pending
  it_behaves_like 'an active conversation', :snoozed

  it 'keeps an initial import backdated, read, resolved, and silent' do
    conversation = create(
      :conversation,
      account: channel.account,
      inbox: inbox,
      contact: contact,
      contact_inbox: contact_inbox,
      status: :open,
      agent_last_seen_at: 1.hour.ago,
      assignee_last_seen_at: 1.hour.ago
    )

    expect { import_history(kind: 'initial', conversation: conversation) }
      .not_to have_enqueued_job(SendReplyJob)

    imported_message = conversation.messages.find_by!(source_id: payload['id'])
    expect(imported_message.created_at).to eq(message_time)
    expect(imported_message.additional_attributes).to include('waha_import_kind' => 'initial', 'imported' => true)
    expect(conversation.status).to eq('resolved')
    expect(conversation.created_at).to eq(message_time)
    expect(conversation.agent_last_seen_at).to be >= imported_message.created_at
    expect(conversation.unread_incoming_messages_count).to eq(0)
  end

  context 'when resolving the chat fails (core failure)' do
    it 'propagates the error and leaves the checkpoint untouched' do
      allow(Waha::ContactResolver).to receive(:from_payload).and_raise(CustomExceptions::Waha::TransientError, 'WAHA unreachable')
      import_chat = WahaImportChat.create!(channel: channel, chat_id: chat_id)
      importer = described_class.new(channel: channel, chat_id: chat_id, window: window, import_chat: import_chat, kind: 'gap_fill')

      expect { importer.run }.to raise_error(CustomExceptions::Waha::TransientError)

      expect(import_chat.reload.cursor).to be_nil
      expect(import_chat.imported_count).to eq(0)
      expect(Message.find_by(source_id: payload['id'])).to be_nil
    end
  end
end
