require 'rails_helper'

# Pins the operational signal contract: which signals exist, which correlation
# fields they carry, which of those may be used as metric dimensions, and what
# must never appear in either. Assertions read notification payloads, never log
# text, so the wording of a log line is free to change.
describe Waha::Telemetry do
  let(:channel) { create(:channel_waha, typing_simulation_enabled: false, auto_read_receipts: false) }
  let(:inbox) { channel.inbox }
  let(:phone) { '5511888888888' }
  let(:chat_jid) { "#{phone}@c.us" }
  let(:contact) { create(:contact, account: channel.account, name: 'John Doe', phone_number: "+#{phone}") }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: chat_jid) }
  let(:conversation) do
    create(:conversation, account: channel.account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
  end

  # Optional enrichment lookups (contact registry, LID resolution) are not part
  # of any signal under test; a blanket miss keeps them out of the way.
  before do
    stub_request(:get, /waha\.test/).to_return(status: 404, body: '{}', headers: { 'Content-Type' => 'application/json' })
  end

  def message_params(stanza: 'AAA111', payload: {})
    {
      'session' => channel.session_name,
      'event' => 'message.any',
      'payload' => {
        'id' => "false_#{chat_jid}_#{stanza}", 'body' => 'a secret sentence', 'from' => chat_jid,
        'to' => '5511999999999@c.us', 'fromMe' => false,
        '_data' => { 'Info' => { 'Chat' => chat_jid, 'PushName' => 'John Doe' } }
      }.merge(payload)
    }
  end

  describe 'correlation' do
    it 'ties a received event and its persisted message to account, inbox, channel, session, chat and both message ids' do
      conversation
      signals = capture_waha_signals { Webhooks::WahaEventsJob.perform_now(channel.id, message_params) }

      received = waha_signal(signals, :event_received).first
      persisted = waha_signal(signals, :message_persisted).first
      message = waha_messages(message_params['payload']['id']).first!

      expect(received).to include(
        account_id: channel.account_id, inbox_id: inbox.id, channel_id: channel.id,
        session: channel.session_name, event: 'message.any', waha_id: 'AAA111'
      )
      expect(persisted).to include(
        waha_id: 'AAA111', direction: :incoming, message_id: message.id, conversation_id: conversation.id
      )
      # The same chat resolves to the same handle across both signals.
      expect(persisted[:chat_ref]).to eq(received[:chat_ref]).and be_present
    end

    it 'follows one identifier from an outgoing send through to the echo that settles it' do
      stub_request(:get, %r{https://waha\.test/api/.+/new-message-id})
        .to_return(status: 200, body: { id: 'GENID001' }.to_json, headers: { 'Content-Type' => 'application/json' })
      stub_request(:post, 'https://waha.test/api/sendText')
        .to_return(status: 201, body: { id: "true_#{chat_jid}_NEW001" }.to_json, headers: { 'Content-Type' => 'application/json' })
      message = create(:message, conversation: conversation, inbox: inbox, account: channel.account,
                                 message_type: :outgoing, content: 'hello')

      sent = capture_waha_signals { Waha::SendOnWahaService.new(message: message).perform }
      confirmed = waha_signal(sent, :delivery_confirmed).first

      expect(confirmed).to include(waha_id: 'NEW001', direction: :outgoing, message_id: message.id, part: 0)

      echo = message_params(stanza: 'NEW001', payload: { 'id' => "true_#{chat_jid}_NEW001", 'fromMe' => true })
      echoed = capture_waha_signals { Webhooks::WahaEventsJob.perform_now(channel.id, echo) }
      deduplicated = waha_signal(echoed, :message_deduplicated).first

      # One identifier, carried from the send request to the event that closes it.
      expect(deduplicated).to include(waha_id: 'NEW001', reason: :chatwoot_echo, message_id: message.id)
      expect(deduplicated[:attempt_id]).to eq(confirmed[:attempt_id])
    end

    it 'reports a webhook redelivery as a deduplication rather than a second message' do
      conversation
      Webhooks::WahaEventsJob.perform_now(channel.id, message_params)

      signals = capture_waha_signals { Webhooks::WahaEventsJob.perform_now(channel.id, message_params) }

      expect(waha_signal(signals, :message_persisted)).to be_empty
      expect(waha_signal(signals, :message_deduplicated).first).to include(reason: :already_mapped, waha_id: 'AAA111')
      expect(waha_messages(message_params['payload']['id']).count).to eq(1)
    end
  end

  describe 'privacy' do
    it 'keeps message content, phone numbers and raw JIDs out of every signal' do
      conversation
      signals = capture_waha_signals { Webhooks::WahaEventsJob.perform_now(channel.id, message_params) }
      values = signals.flat_map { |_signal, payload| payload.except(:tags).values.map(&:to_s) }

      expect(signals).not_to be_empty
      expect(values).to all(satisfy { |value| [phone, 'a secret sentence', '@c.us'].none? { |secret| value.include?(secret) } })
    end

    it 'resolves a chat to a stable handle that does not disclose the chat itself' do
      ref = described_class.chat_ref(chat_jid)

      expect(ref).to eq(described_class.chat_ref(chat_jid))
      expect(ref).not_to include(phone)
      expect(ref).not_to eq(described_class.chat_ref('5511777777777@c.us'))
      expect(described_class.chat_ref('12036@g.us')).to start_with('g-')
    end

    it 'collapses the phone forms of one identity into a single handle' do
      ref = described_class.chat_ref(chat_jid)

      expect(described_class.chat_ref("#{phone}@s.whatsapp.net")).to eq(ref)
      expect(described_class.chat_ref("#{phone}:23@s.whatsapp.net")).to eq(ref)
    end

    # Documented limit, not an oversight: LID -> phone lives in
    # waha_contact_aliases, and a signal must not add a query per log line.
    # Live GOWS traffic delivers ~26% of direct messages under @lid while their
    # canonical mapping is @c.us, so the two forms are joined by waha_id.
    it 'gives an @lid its own handle rather than querying the alias table' do
      expect(described_class.chat_ref('85693321732330@lid')).not_to eq(described_class.chat_ref(chat_jid))
      expect(described_class.chat_ref('85693321732330@lid')).to start_with('d-')
    end
  end

  describe 'cardinality' do
    it 'exposes only closed-vocabulary fields as metric dimensions' do
      conversation
      signals = capture_waha_signals { Webhooks::WahaEventsJob.perform_now(channel.id, message_params) }

      signals.map(&:last).each do |payload|
        expect(payload[:tags].keys).to all(be_in(described_class::TAG_KEYS))
        expect(payload[:tags].values).to all(match(/\A[a-z0-9._-]{0,40}\z/))
      end
      # The free-form identifiers stay in the payload and out of the dimensions.
      expect(waha_signal(signals, :event_received).first[:tags]).not_to include(:waha_id, :chat_ref, :session)
    end

    it 'reduces an unrecognised event name to a bounded token' do
      signals = capture_waha_signals do
        Webhooks::WahaEventsJob.perform_now(channel.id, { 'session' => channel.session_name, 'event' => "wat ever/#{phone}" })
      end
      ignored = waha_signal(signals, :event_ignored).first

      expect(ignored).to include(reason: :unsupported_event)
      expect(ignored[:tags][:event]).to eq('wat_ever_5511888888888'.first(40)).and match(/\A[a-z0-9._-]+\z/)
    end
  end

  describe 'distinguishable operational conditions' do
    it 'reports a webhook carrying another session as a divergent session, not as an unsupported event' do
      signals = capture_waha_signals do
        Webhooks::WahaEventsJob.perform_now(channel.id, message_params.merge('session' => 'someone_elses'))
      end

      expect(waha_signal(signals, :event_ignored).first).to include(reason: :session_mismatch)
      expect(waha_signal(signals, :event_received)).to be_empty
    end

    it 'reports a message type it cannot convert, naming the shape and not its contents' do
      conversation
      params = message_params(payload: { 'body' => nil, '_data' => { 'Info' => { 'Chat' => chat_jid },
                                                                     'Message' => { 'newFangledMessage' => { 'secret' => 'value' } } } })

      signals = capture_waha_signals { Webhooks::WahaEventsJob.perform_now(channel.id, params) }
      unsupported = waha_signal(signals, :message_unsupported_type).first

      expect(unsupported).to include(reason: 'newFangledMessage', waha_id: 'AAA111')
      expect(unsupported.except(:tags).values.map(&:to_s)).not_to include('value')
    end

    it 'reports an ambiguous send attempt separately from a plain retry' do
      stub_request(:get, %r{https://waha\.test/api/.+/new-message-id})
        .to_return(status: 200, body: { id: 'GENID001' }.to_json, headers: { 'Content-Type' => 'application/json' })
      stub_request(:post, 'https://waha.test/api/sendText').to_return(status: 500, body: 'boom')
      stub_request(:get, %r{https://waha\.test/api/.+/chats/.+/messages\?.*})
        .to_return(status: 200, body: [{ 'id' => "true_#{chat_jid}_GENID001" }].to_json, headers: { 'Content-Type' => 'application/json' })
      message = create(:message, conversation: conversation, inbox: inbox, account: channel.account,
                                 message_type: :outgoing, content: 'hello')

      signals = capture_waha_signals { Waha::SendOnWahaService.new(message: message).perform }

      expect(waha_signal(signals, :delivery_ambiguous).first).to include(outcome: :recovered, direction: :outgoing, message_id: message.id)
      expect(waha_signal(signals, :delivery_retry_scheduled)).to be_empty
      expect(waha_signal(signals, :delivery_confirmed).first).to include(waha_id: 'GENID001')
    end

    it 'reports a chat whose history makes no progress as a stall' do
      # A full page spread over several seconds (so it is not an ambiguous
      # same-second cluster) that sits entirely at or before the confirmed
      # cursor: the engine keeps returning work already done.
      page = Array.new(Waha::ChatHistoryImporter::PAGE_SIZE) do |index|
        { 'id' => "false_#{chat_jid}_OLD#{index}", 'timestamp' => 1_700_000_000 + (index % 10), 'body' => 'old',
          'from' => chat_jid, '_data' => { 'Info' => { 'Chat' => chat_jid } } }
      end
      stub_request(:get, %r{https://waha\.test/api/.+/chats/.+/messages\?.*})
        .to_return(status: 200, body: page.to_json, headers: { 'Content-Type' => 'application/json' })
      row = channel.import_chats.create!(chat_id: chat_jid, cursor: 1_700_000_100, cursor_message_id: 'ZZZZZZ')
      window = { 'window_start' => '2023-01-01T00:00:00Z', 'window_end' => '2030-01-01T00:00:00Z' }

      signals = capture_waha_signals do
        expect do
          Waha::ChatHistoryImporter.new(channel: channel, chat_id: chat_jid, window: window, import_chat: row).run
        end.to raise_error(CustomExceptions::Waha::ApiError)
      end

      expect(waha_signal(signals, :import_stalled).first).to include(reason: :no_progress, kind: 'initial')
    end
  end

  describe 'media and import progress' do
    it 'separates a transient media download from the terminal give-up' do
      conversation
      params = message_params(payload: { 'body' => nil, 'hasMedia' => true, 'type' => 'image',
                                         'media' => { 'url' => 'http://localhost:3000/api/files/abc.jpeg', 'mimetype' => 'image/jpeg' } })
      stub_request(:get, 'https://waha.test/api/files/abc.jpeg').to_return(status: 503)

      transient = capture_waha_signals { Webhooks::WahaEventsJob.perform_now(channel.id, params) }
      terminal = capture_waha_signals do
        Webhooks::WahaEventsJob.perform_now(channel.id, params, 0, Webhooks::WahaEventsJob::MEDIA_MAX_ATTEMPTS)
      end

      expect(waha_signal(transient, :media_download).first).to include(outcome: :transient, scope: :live, try: 1, waha_id: 'AAA111')
      expect(waha_signal(terminal, :media_download).first).to include(outcome: :terminal, reason: :retries_exhausted, scope: :live)
    end

    it 'reports how long an import ran and how much of it landed' do
      channel.update_import_state!('status' => 'running', 'kind' => 'gap_fill', 'execution_id' => 'exec-1',
                                   'started_at' => 30.seconds.ago.utc.iso8601)

      signals = capture_waha_signals { channel.finish_import! }
      finished = waha_signal(signals, :import_finished).first

      expect(finished).to include(outcome: :completed, kind: 'gap_fill', execution_id: 'exec-1', channel_id: channel.id)
      expect(finished[:duration_ms]).to be_within(5_000).of(30_000)
    end

    it 'reports a pending event backlog while it retries, then its terminal exhaustion' do
      ack = { 'session' => channel.session_name, 'event' => 'message.ack',
              'payload' => { 'id' => "true_#{chat_jid}_GHOST1", 'ack' => 2, 'from' => chat_jid } }

      retried = capture_waha_signals { Webhooks::WahaEventsJob.perform_now(channel.id, ack, 0) }
      exhausted = capture_waha_signals { Webhooks::WahaEventsJob.perform_now(channel.id, ack, Webhooks::WahaEventsJob::ACK_MAX_RETRIES) }

      expect(waha_signal(retried, :event_retry_scheduled).first).to include(reason: :missing_anchor, try: 0, waha_id: 'GHOST1')
      expect(waha_signal(exhausted, :event_retries_exhausted).first).to include(reason: :missing_anchor, waha_id: 'GHOST1')
    end
  end
end
