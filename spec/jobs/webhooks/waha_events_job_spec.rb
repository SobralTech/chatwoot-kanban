require 'rails_helper'

describe Webhooks::WahaEventsJob do
  let(:channel) { create(:channel_waha) }
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: channel.account, name: 'John Doe', phone_number: '+5511888888888') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5511888888888@c.us') }
  let(:conversation) do
    create(:conversation, account: channel.account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
  end
  let(:media_url) { 'https://waha.test/api/files/abc.jpeg' }

  before do
    stub_request(:get, /waha\.test/).to_return(status: 404, body: '{}', headers: { 'Content-Type' => 'application/json' })
  end

  def media_message_params(stanza: 'MEDIA01')
    {
      'session' => channel.session_name,
      'event' => 'message.any',
      'payload' => {
        'id' => "false_5511888888888@c.us_#{stanza}",
        'body' => nil,
        'from' => '5511888888888@c.us',
        'to' => '5511999999999@c.us',
        'fromMe' => false,
        'type' => 'image',
        'hasMedia' => true,
        'media' => { 'url' => 'http://localhost:3000/api/files/abc.jpeg', 'mimetype' => 'image/jpeg' },
        '_data' => { 'Info' => { 'Chat' => '5511888888888@c.us', 'PushName' => 'John Doe' } }
      }
    }
  end

  describe 'live media recovery' do
    it 'keeps a transient download failure retryable instead of persisting an incomplete message' do
      conversation
      stub_request(:get, media_url).to_return(status: 503)
      params = media_message_params

      expect { described_class.perform_now(channel.id, params) }
        .to have_enqueued_job(described_class)
        .with(channel.id, params, 0, 2)
        .at(a_value_within(1.second).of(described_class::MEDIA_RETRY_DELAYS[0].from_now))

      expect(waha_messages(params['payload']['id'], Message.all).first).to be_nil
    end

    it 'creates exactly one message with its attachment once the download recovers, with no duplicate on redelivery' do
      conversation
      params = media_message_params
      stub_request(:get, media_url).to_return(status: 503)
      described_class.perform_now(channel.id, params)
      expect(waha_messages(params['payload']['id'], Message.all).count).to eq(0)

      stub_request(:get, media_url).to_return(status: 200, body: 'bytes', headers: { 'Content-Type' => 'image/jpeg' })
      described_class.perform_now(channel.id, params, 0, 2)

      message = waha_messages(params['payload']['id'], Message.all).first!
      expect(message.attachments.size).to eq(1)

      # WAHA (or Sidekiq) redelivering the same event afterwards must not duplicate it.
      described_class.perform_now(channel.id, params, 0, 2)
      expect(waha_messages(params['payload']['id'], Message.all).count).to eq(1)
    end

    it 'persists the message with a visible fallback after exhausting retries, without scheduling another one' do
      conversation
      params = media_message_params
      stub_request(:get, media_url).to_return(status: 503)

      # The final attempt still tries the network once for real; only once that
      # also fails does it fall back, without a second (wasted) download attempt.
      expect { described_class.perform_now(channel.id, params, 0, described_class::MEDIA_MAX_ATTEMPTS) }
        .not_to have_enqueued_job(described_class)

      expect(a_request(:get, media_url)).to have_been_made.once
      message = waha_messages(params['payload']['id'], Message.all).first!
      expect(message.attachments).to be_empty
      expect(message.content_attributes['media_download_failed']).to be(true)
      expect(message.content).to eq(I18n.t('conversations.messages.waha_media_unavailable'))
    end

    # The placeholder is persisted, and this job runs in Sidekiq where
    # I18n.locale is the process default — so without the account's locale the
    # text is frozen into the message in English no matter what the inbox is
    # read in.
    it 'writes the fallback in the account language' do
      channel.account.update!(locale: 'pt_BR')
      conversation
      stub_request(:get, media_url).to_return(status: 404)
      params = media_message_params(stanza: 'MEDIALOCALE')

      described_class.perform_now(channel.id, params, 0, described_class::MEDIA_MAX_ATTEMPTS)

      message = waha_messages(params['payload']['id'], Message.all).first!
      expect(message.content).to eq(I18n.t('conversations.messages.waha_media_unavailable', locale: :pt_BR))
      expect(message.content).to eq('Mídia indisponível: o download falhou após várias tentativas')
    end
  end

  def own_message_params(stanza:, source: 'api')
    {
      'session' => channel.session_name,
      'event' => 'message.any',
      'payload' => {
        'id' => "true_5511888888888@c.us_#{stanza}",
        'body' => 'hello from elsewhere',
        'from' => '5511999999999@c.us',
        'to' => '5511888888888@c.us',
        'fromMe' => true,
        'source' => source,
        'type' => 'chat',
        'hasMedia' => false,
        '_data' => { 'Info' => { 'Chat' => '5511888888888@c.us' } }
      }
    }
  end

  def plain_message_params(stanza:, body: 'hi', reply_to: nil)
    payload = {
      'id' => "false_5511888888888@c.us_#{stanza}",
      'body' => body,
      'from' => '5511888888888@c.us',
      'to' => '5511999999999@c.us',
      'fromMe' => false,
      'type' => 'chat',
      'hasMedia' => false,
      '_data' => { 'Info' => { 'Chat' => '5511888888888@c.us', 'PushName' => 'John Doe' } }
    }
    payload['replyTo'] = reply_to if reply_to
    { 'session' => channel.session_name, 'event' => 'message.any', 'payload' => payload }
  end

  # Shape confirmed against the GOWS engine adapter: the edit's own `id` is a
  # fresh envelope (`${fromMe}_${chatJid}_${info.ID}`, same as any other
  # message), while `editedMessageId` carries the bare original WhatsApp
  # message id (`protocolMessage.key.ID`, no chat/direction prefix) — never the
  # id of an intermediate edit, since every edit on the wire targets the same
  # original stanza.
  def edited_message_params(edited_message_id:, stanza:, body: 'edited text', from_me: false)
    {
      'session' => channel.session_name,
      'event' => 'message.edited',
      'payload' => {
        'id' => "#{from_me}_5511888888888@c.us_#{stanza}",
        'body' => body,
        'editedMessageId' => edited_message_id,
        'from' => from_me ? '5511999999999@c.us' : '5511888888888@c.us',
        'to' => from_me ? '5511888888888@c.us' : '5511999999999@c.us',
        'fromMe' => from_me,
        'type' => 'chat',
        'hasMedia' => false,
        '_data' => { 'Info' => { 'Chat' => '5511888888888@c.us' } }
      }
    }
  end

  describe 'message edits (real GOWS payload shape)' do
    let(:original) do
      create_waha_message(conversation: conversation, inbox: inbox, account: channel.account,
                          source_id: 'false_5511888888888@c.us_AAA111', content: 'original text')
    end

    it 'persists and anchors the new version, then supersedes the original' do
      original
      params = edited_message_params(edited_message_id: 'AAA111', stanza: 'EDIT01')

      described_class.perform_now(channel.id, params)

      edited = waha_messages('false_5511888888888@c.us_EDIT01', Message.all).first!
      expect(Waha::Anchoring.family_anchor_message(edited)).to eq(original)
      expect(edited.content).to include('edited text')
      expect(edited.additional_attributes['superseded']).to be_blank
      expect(original.reload.additional_attributes['superseded']).to be(true)
    end

    it 'leaves the original intact and un-superseded when persisting the new version fails' do
      original
      params = edited_message_params(edited_message_id: 'AAA111', stanza: 'EDIT02')
      allow_any_instance_of(Waha::IncomingMessageService).to receive(:perform).and_raise(StandardError, 'boom') # rubocop:disable RSpec/AnyInstance

      expect { described_class.perform_now(channel.id, params) }.to raise_error(StandardError, 'boom')

      expect(original.reload.additional_attributes['superseded']).to be_blank
      expect(Message.exists?(source_id: 'false_5511888888888@c.us_EDIT02')).to be(false)
    end

    it 'keeps an edit that arrives before its base message pending and reapplies it once the base lands' do
      params = edited_message_params(edited_message_id: 'BASE01', stanza: 'EDIT03')

      expect { described_class.perform_now(channel.id, params) }
        .to have_enqueued_job(described_class)
        .with(channel.id, params, 1)
        .at(a_value_within(1.second).of(described_class::ACK_RETRY_DELAY.from_now))
      expect(Message.exists?(source_id: 'false_5511888888888@c.us_EDIT03')).to be(false)

      base = create_waha_message(conversation: conversation, inbox: inbox, account: channel.account,
                                 source_id: 'false_5511888888888@c.us_BASE01', content: 'original text')

      described_class.perform_now(channel.id, params, 1)

      edited = waha_messages('false_5511888888888@c.us_EDIT03', Message.all).first!
      expect(Waha::Anchoring.family_anchor_message(edited)).to eq(base)
      expect(base.reload.additional_attributes['superseded']).to be(true)
    end

    it 'keeps replies anchored to the original while quoting the current edit head' do
      original
      described_class.perform_now(channel.id, edited_message_params(edited_message_id: 'AAA111', stanza: 'EDIT04'))
      head = waha_messages('false_5511888888888@c.us_EDIT04', Message.all).first!

      reply_params = plain_message_params(stanza: 'REPLY01', body: 'quoting the edited message', reply_to: { 'id' => 'AAA111' })
      described_class.perform_now(channel.id, reply_params)

      reply = waha_messages(reply_params['payload']['id'], Message.all).first!
      expect(reply.content_attributes['in_reply_to']).to eq(head.id)
      expect(reply.content_attributes['in_reply_to_external_id']).to eq(original.presented_source_id)
    end

    it 'uses the GOWS edit envelope and points a reply at the family head' do
      original = create_waha_message(conversation: conversation, inbox: inbox, account: channel.account,
                                     source_id: 'false_5511888888888@c.us_3EB0EDITBASE', content: 'texto original')
      edit_params = gows_event('message_edited')
      edit_params['session'] = channel.session_name

      described_class.perform_now(channel.id, edit_params)

      head = waha_messages('false_5511888888888@c.us_3EB0EDIT01', Message.all).first!
      reply_params = {
        'session' => channel.session_name,
        'event' => 'message.any',
        'payload' => gows_payload('reply_to_edit')
      }
      described_class.perform_now(channel.id, reply_params)

      reply = waha_messages('false_5511888888888@c.us_3EB0REPLYEDIT01', Message.all).first!
      expect(reply.content_attributes).to include(
        'in_reply_to' => head.id,
        'in_reply_to_external_id' => original.presented_source_id
      )
    end
  end

  describe 'fromMe echo correlation' do
    it 'absorbs a fromMe event correlated to a pending Chatwoot delivery attempt, without mirroring it' do
      conversation
      outgoing = create_waha_message(conversation: conversation, inbox: inbox, account: channel.account, message_type: :outgoing)
      attempt = WahaDeliveryAttempt.create!(channel: channel, message: outgoing, chat_jid: '5511888888888@c.us',
                                            status: :sending, client_message_id: 'ECHOID1', dispatched_at: Time.current)
      params = own_message_params(stanza: 'ECHOID1')
      attempt.delivery_parts.create!(position: 0, part_type: :text, client_message_id: 'ECHOID1', dispatched_at: Time.current)

      expect(Waha::IncomingMessageService).not_to receive(:new)

      described_class.perform_now(channel.id, params)

      expect(attempt.reload.status).to eq('sent')
      expect(attempt.delivery_parts.first.external_id).to eq('ECHOID1')
      expect(outgoing.reload.presented_source_id).to eq('true_5511888888888@c.us_ECHOID1')
    end

    it 'is idempotent when WAHA redelivers the same correlated echo' do
      conversation
      outgoing = create_waha_message(conversation: conversation, inbox: inbox, account: channel.account, message_type: :outgoing)
      WahaDeliveryAttempt.create!(channel: channel, message: outgoing, chat_jid: '5511888888888@c.us',
                                  status: :sending, client_message_id: 'ECHOID2', dispatched_at: Time.current)
      params = own_message_params(stanza: 'ECHOID2')

      described_class.perform_now(channel.id, params)
      described_class.perform_now(channel.id, params)

      expect(WahaMessageMapping.where(channel: channel, external_id: 'ECHOID2').count).to eq(1)
    end

    it 'mirrors an uncorrelated fromMe event (e.g. sent by another API on the same session) instead of dropping it' do
      conversation
      params = own_message_params(stanza: 'OTHERAPI1')

      described_class.perform_now(channel.id, params)

      message = waha_messages(params['payload']['id'], Message.all).first
      expect(message).to be_present
      expect(message).to have_attributes(message_type: 'outgoing')
    end
  end

  describe 'GOWS calls' do
    def call_params(event: 'call.received', overrides: {})
      {
        'session' => channel.session_name,
        'event' => event,
        'payload' => {
          'id' => 'CALLWEBHOOK01',
          'from' => '5511888888888@c.us',
          'timestamp' => 1_762_358_460,
          'isVideo' => false,
          'isGroup' => false,
          '_data' => { 'Data' => { 'Attrs' => {} } }
        }.merge(overrides)
      }
    end

    it 'routes a supported direct call to a conversation activity without initiating voice or video' do
      conversation

      expect { described_class.perform_now(channel.id, call_params) }.to change { conversation.reload.messages.activity.count }.by(1)

      event = conversation.messages.activity.last
      expect(event.content_attributes['waha_call']).to include(
        'direction' => 'incoming', 'participant_jid' => '5511888888888@c.us', 'result' => 'received', 'is_video' => false
      )
    end

    it 'leaves unsupported group calls out of the conversation and emits an operational decision' do
      signals = capture_waha_signals do
        expect { described_class.perform_now(channel.id, call_params(overrides: { 'isGroup' => true })) }.not_to change(Message, :count)
      end

      expect(waha_signal(signals, :event_ignored).first).to include(event: 'call.received', reason: :group_call)
    end

    it 'records a malformed call decision instead of silently dropping the webhook' do
      signals = capture_waha_signals do
        expect { described_class.perform_now(channel.id, 'session' => channel.session_name, 'event' => 'call.received') }
          .not_to change(Message, :count)
      end

      expect(waha_signal(signals, :event_ignored).first).to include(event: 'call.received', reason: :missing_call_id)
    end
  end

  describe 'multipart event correlation' do
    it 'applies an ack for any mapped part to the aggregate Chatwoot message' do
      outgoing = create_waha_message(conversation: conversation, inbox: inbox, account: channel.account,
                                     message_type: :outgoing, source_id: 'true_5511888888888@c.us_FIRST', status: :sent)
      WahaMessageMapping.create_canonical!(channel: channel, message: outgoing, chat_jid: contact_inbox.source_id,
                                           external_id: 'SECOND', direction: :outgoing, part: 1)
      params = {
        'session' => channel.session_name,
        'event' => 'message.ack',
        'payload' => { 'id' => 'true_5511888888888@c.us_SECOND', 'ack' => 2 }
      }

      described_class.perform_now(channel.id, params)

      expect(outgoing.reload.status).to eq('delivered')
    end
  end

  describe 'GOWS poll votes' do
    it 'updates the matching poll in its conversation without creating a second poll and is idempotent on redelivery' do
      conversation
      poll = Waha::IncomingMessageService.new(channel: channel, payload: gows_payload('poll_creation')).perform
      params = gows_event('poll_vote')
      params['session'] = channel.session_name

      expect { described_class.perform_now(channel.id, params) }.not_to change(Message, :count)

      expect(poll.reload.content).to include("Observed votes\n• Terça-feira — 1 vote")
      expect(poll.content_attributes['poll_votes']).to eq(
        '5511888888888@c.us' => { 'selected_options' => ['Terça-feira'], 'timestamp' => 1_762_358_460_000 }
      )
      expect(WahaMessageMapping.find_by!(message: poll, event_type: :poll_vote)).to have_attributes(
        external_id: 'VOTE01', chat_jid: contact_inbox.source_id, direction: 'incoming'
      )

      described_class.perform_now(channel.id, params)

      expect(Message.where(conversation: conversation).count).to eq(1)
      expect(WahaMessageMapping.where(message: poll, event_type: :poll_vote).count).to eq(1)
    end

    it 'keeps a vote pending when its poll has not been persisted yet' do
      params = gows_event('poll_vote')
      params['session'] = channel.session_name

      expect { described_class.perform_now(channel.id, params) }
        .to have_enqueued_job(described_class)
        .with(channel.id, params, 1)
        .at(a_value_within(1.second).of(described_class::ACK_RETRY_DELAY.from_now))
    end
  end

  describe 'delivery acks' do
    let(:group_contact_inbox) do
      create(:contact_inbox, inbox: inbox, source_id: '1203630000@g.us', contact: create(:contact, account: channel.account))
    end
    let(:group_conversation) do
      create(:conversation, account: channel.account, inbox: inbox, contact: group_contact_inbox.contact,
                            contact_inbox: group_contact_inbox)
    end

    def ack_params(event:, payload:)
      { 'session' => channel.session_name, 'event' => event, 'payload' => payload }
    end

    it 'keeps an ack that arrives before its message pending and reapplies it once the message lands' do
      params = ack_params(event: 'message.ack', payload: { 'id' => 'true_5511888888888@c.us_LATE01', 'ack' => 3 })

      expect { described_class.perform_now(channel.id, params) }
        .to have_enqueued_job(described_class)
        .with(channel.id, params, 1)
        .at(a_value_within(1.second).of(described_class::ACK_RETRY_DELAY.from_now))

      outgoing = create_waha_message(conversation: conversation, inbox: inbox, account: channel.account,
                                     message_type: :outgoing, status: :sent, source_id: 'true_5511888888888@c.us_LATE01')
      described_class.perform_now(channel.id, params, 1)

      expect(outgoing.reload.status).to eq('read')
    end

    it 'routes a group ack to the message the participant read' do
      outgoing = create_waha_message(conversation: group_conversation, inbox: inbox, account: channel.account,
                                     message_type: :outgoing, status: :sent,
                                     source_id: 'true_1203630000@g.us_GRP001_5511999999999@c.us')
      params = ack_params(
        event: 'message.ack.group',
        payload: { 'id' => 'true_1203630000@g.us_GRP001_5511999999999@c.us', 'from' => '1203630000@g.us',
                   'to' => '5511777777777@c.us', 'participant' => '5511777777777@c.us', 'fromMe' => true, 'ack' => 3 }
      )

      described_class.perform_now(channel.id, params)

      expect(outgoing.reload.status).to eq('read')
      expect(outgoing.content_attributes['waha_group_acks']).to eq('5511777777777@c.us' => 'read')
    end
  end

  describe 'session isolation' do
    it 'does not route an event without a session' do
      params = media_message_params.except('session')

      expect(Waha::IncomingMessageService).not_to receive(:new)

      described_class.perform_now(channel.id, params)
    end

    it 'does not route an event whose session does not belong to the channel' do
      params = media_message_params.merge('session' => 'another_session')

      expect(Waha::IncomingMessageService).not_to receive(:new)

      described_class.perform_now(channel.id, params)
    end

    it 'routes an event whose session matches the channel' do
      conversation
      params = media_message_params.merge('session' => channel.session_name)
      stub_request(:get, media_url).to_return(status: 200, body: 'bytes', headers: { 'Content-Type' => 'image/jpeg' })

      described_class.perform_now(channel.id, params)

      expect(waha_messages(params['payload']['id'], Message.all).count).to eq(1)
    end
  end
end
