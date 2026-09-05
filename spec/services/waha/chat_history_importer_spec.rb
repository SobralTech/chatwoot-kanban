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

      mapping = WahaMessageMapping.find_by!(message: recovered_message)
      expect(mapping).to have_attributes(chat_jid: chat_id, external_id: 'GAPFILL001', direction: 'incoming', event_type: 'message')
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

  context 'with composite cursor pagination' do
    # Simulates the GOWS contract the importer actually relies on: sortBy
    # timestamp, an inclusive filter.timestamp.gte/lte window and a hard
    # `limit` — but NOT any particular order among same-second messages
    # (see SPEC.md). The response for a given call is sliced from `messages`
    # in whatever order the test built that array, independent of any
    # "chronological" or id-sorted order, so a pass here can't be an
    # accident of the array already being pre-sorted the way the importer
    # wants it.
    def stub_history_messages(messages)
      stub_request(:get, %r{https://waha\.test/api/#{channel.session_name}/chats/#{Regexp.escape(chat_id)}/messages\?})
        .to_return do |request|
          params = Rack::Utils.parse_query(URI(request.uri).query)
          gte = params['filter.timestamp.gte'].to_i
          lte = params['filter.timestamp.lte'].to_i
          page = messages.select { |m| m['timestamp'].to_i.between?(gte, lte) }.first(params['limit'].to_i)
          { status: 200, body: page.to_json, headers: { 'Content-Type' => 'application/json' } }
        end
    end

    def build_payloads(count:, base_ts:, prefix:, ts_step: 0)
      Array.new(count) do |i|
        {
          'id' => "false_#{chat_id}_#{prefix}#{i.to_s.rjust(4, '0')}",
          'body' => "msg #{i}",
          'from' => chat_id,
          'to' => '5511999999999@c.us',
          'fromMe' => false,
          'timestamp' => base_ts + (i * ts_step),
          'type' => 'chat',
          'hasMedia' => false,
          '_data' => { 'Info' => { 'Chat' => chat_id, 'PushName' => 'Jane Doe' } }
        }
      end
    end

    it 'fully imports a same-second cluster larger than the page size, without loss, duplication or a fabricated order' do
      tied_ts = message_time.to_i
      messages = build_payloads(count: described_class::PAGE_SIZE + 50, base_ts: tied_ts, prefix: 'TIE').shuffle
      stub_history_messages(messages)

      conversation = create(:conversation, account: channel.account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
      import_chat = WahaImportChat.create!(channel: channel, chat_id: chat_id)

      imported = described_class.new(
        channel: channel, chat_id: chat_id, window: window, import_chat: import_chat, kind: 'initial'
      ).run

      expect(imported).to eq(messages.size)
      expect(conversation.messages.where.not(source_id: nil).pluck(:source_id)).to match_array(messages.pluck('id'))
      import_chat.reload
      expect(import_chat.imported_count).to eq(messages.size)
      # Every message in the cluster is confirmed, so the checkpoint has
      # stepped one second past it with no id yet confirmed there.
      expect(import_chat.cursor).to eq(tied_ts + 1)
      expect(import_chat.cursor_message_id).to be_nil
    end

    it 'resumes from a persisted composite checkpoint without losing or duplicating messages' do
      base_ts = message_time.to_i
      payloads = build_payloads(count: 300, base_ts: base_ts, prefix: 'RES', ts_step: 1)
      stub_history_messages(payloads)

      conversation = create(:conversation, account: channel.account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
      already_confirmed = payloads.first(220)
      already_confirmed.each do |p|
        create(:message, conversation: conversation, inbox: inbox, account: channel.account,
                         message_type: :incoming, source_id: p['id'], created_at: Time.zone.at(p['timestamp']))
      end
      checkpoint = already_confirmed.last
      import_chat = WahaImportChat.create!(
        channel: channel, chat_id: chat_id, cursor: checkpoint['timestamp'],
        cursor_message_id: 'RES0219', imported_count: already_confirmed.size
      )

      imported = described_class.new(
        channel: channel, chat_id: chat_id, window: window, import_chat: import_chat, kind: 'gap_fill'
      ).run

      expect(imported).to eq(80)
      expect(conversation.messages.where.not(source_id: nil).count).to eq(300)
      expect(conversation.messages.pluck(:source_id).uniq.size).to eq(300)
      import_chat.reload
      expect(import_chat.imported_count).to eq(300)
      expect(import_chat.cursor).to eq(payloads.last['timestamp'])
      expect(import_chat.cursor_message_id).to eq('RES0299')

      # A superfluous re-run (e.g. a periodic sweep after the chat already
      # fully caught up) must terminate cleanly, not mistake "nothing left"
      # for a stall.
      again = described_class.new(
        channel: channel, chat_id: chat_id, window: window, import_chat: import_chat, kind: 'gap_fill'
      ).run
      expect(again).to eq(0)
    end

    it 'raises an observable error instead of looping or falsely completing when a full page makes no progress' do
      stale_ts = message_time.to_i
      # Distinct timestamps (not a tied second) so this exercises the plain
      # stall path, not same-second cluster resolution.
      stale_messages = build_payloads(count: described_class::PAGE_SIZE, base_ts: stale_ts, prefix: 'STALL', ts_step: 1)
      # An engine that ignores the gte/lte filters entirely and always
      # returns the same full page — every one of these was already
      # confirmed by the persisted checkpoint below, so no page can ever
      # make progress.
      stub_request(:get, %r{https://waha\.test/api/#{channel.session_name}/chats/#{Regexp.escape(chat_id)}/messages\?})
        .to_return(status: 200, body: stale_messages.to_json, headers: { 'Content-Type' => 'application/json' })

      last = stale_messages.last
      import_chat = WahaImportChat.create!(
        channel: channel, chat_id: chat_id, cursor: last['timestamp'], cursor_message_id: 'STALL0199', imported_count: 200
      )
      importer = described_class.new(
        channel: channel, chat_id: chat_id, window: window, import_chat: import_chat, kind: 'gap_fill'
      )

      expect { importer.run }.to raise_error(CustomExceptions::Waha::ApiError, /stalled/)

      import_chat.reload
      expect(import_chat.cursor).to eq(last['timestamp'])
      expect(import_chat.cursor_message_id).to eq('STALL0199')
      expect(import_chat.imported_count).to eq(200)
    end
  end

  context 'with a malformed GOWS structured message' do
    it 'writes a visible fallback instead of a blank historical message' do
      # The incomplete poll has no options. A complete pollCreationMessage is
      # converted by Ticket 20; this keeps the invalid-payload fallback contract.
      unsupported_payload = {
        'id' => 'false_5511888888888@c.us_POLL001',
        'from' => chat_id,
        'to' => '5511999999999@c.us',
        'fromMe' => false,
        'timestamp' => message_time.to_i,
        'hasMedia' => false,
        '_data' => {
          'Info' => { 'Chat' => chat_id, 'PushName' => 'Jane Doe' },
          'Message' => { 'pollCreationMessage' => { 'name' => 'Qual dia é melhor?' } }
        }
      }
      stub_request(:get, %r{https://waha\.test/api/#{channel.session_name}/chats/5511888888888@c\.us/messages\?})
        .to_return(status: 200, body: [unsupported_payload].to_json, headers: { 'Content-Type' => 'application/json' })

      conversation = create(:conversation, account: channel.account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
      import_history(kind: 'initial', conversation: conversation)

      message = conversation.messages.find_by!(source_id: unsupported_payload['id'])
      expect(message.content_attributes['is_unsupported']).to be(true)
      expect(message.attachments).to be_empty
    end
  end
end
