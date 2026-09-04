require 'rails_helper'

describe Waha::IncomingMessageService do
  let(:channel) { create(:channel_waha) }
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: channel.account, name: 'John Doe', phone_number: '+5511888888888') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5511888888888@c.us') }
  let(:conversation) do
    create(:conversation, account: channel.account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
  end

  before do
    stub_request(:get, /waha\.test/).to_return(status: 404, body: '{}', headers: { 'Content-Type' => 'application/json' })
  end

  def build_payload(stanza:, reply_to: nil, body: 'a reply')
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
    payload
  end

  def perform(payload, edited_original: nil)
    described_class.new(channel: channel, payload: payload, edited_original: edited_original).perform
  end

  describe 'reply context resolution' do
    context 'when the quoted message is in the same conversation' do
      it 'stores a local clickable quote' do
        quoted = create(:message, conversation: conversation, inbox: inbox, account: channel.account,
                                  source_id: 'false_5511888888888@c.us_AAA111')

        perform(build_payload(stanza: 'BBB222', reply_to: { 'id' => 'AAA111' }))

        message = conversation.reload.messages.last
        expect(message.content_attributes['in_reply_to']).to eq(quoted.id)
        expect(message.content_attributes['in_reply_to_external_id']).to eq(quoted.source_id)
        expect(message.content_attributes['in_reply_to_snapshot']).to be_nil
      end
    end

    context 'when the quoted message has edit mirrors' do
      it 'points the quote at the newest edit mirror and keeps the anchor as external id' do
        original = create(:message, conversation: conversation, inbox: inbox, account: channel.account,
                                    source_id: 'false_5511888888888@c.us_AAA111')
        head = create(:message, conversation: conversation, inbox: inbox, account: channel.account,
                                source_id: 'false_5511888888888@c.us_EDIT01',
                                additional_attributes: { 'edit_of' => original.source_id })

        perform(build_payload(stanza: 'BBB222', reply_to: { 'id' => 'AAA111' }))

        message = conversation.reload.messages.last
        expect(message.content_attributes['in_reply_to']).to eq(head.id)
        expect(message.content_attributes['in_reply_to_external_id']).to eq(original.source_id)
      end
    end

    context 'when the quoted message is in another conversation' do
      it 'stores a ghost snapshot built from the local message content' do
        other_conversation = create(:conversation, account: channel.account, inbox: inbox, contact: contact,
                                                   contact_inbox: contact_inbox, status: :resolved)
        quoted = create(:message, conversation: other_conversation, inbox: inbox, account: channel.account,
                                  message_type: :incoming, sender: contact, content: 'the old answer',
                                  source_id: 'false_5511888888888@c.us_AAA111')
        conversation

        perform(build_payload(stanza: 'BBB222', reply_to: { 'id' => 'AAA111' }))

        message = conversation.reload.messages.last
        expect(message.content_attributes['in_reply_to']).to be_nil
        expect(message.content_attributes['in_reply_to_external_id']).to eq(quoted.source_id)
        expect(message.content_attributes['in_reply_to_snapshot']).to eq(
          'body' => 'the old answer', 'author' => contact.name
        )
      end
    end

    context 'when the quoted message does not exist locally' do
      it 'stores a ghost snapshot from the payload body and participant' do
        conversation

        perform(
          build_payload(
            stanza: 'BBB222',
            reply_to: { 'id' => 'ZZZ999', 'body' => 'an old message', 'participant' => '5511888888888@c.us' }
          )
        )

        message = conversation.reload.messages.last
        expect(message.content_attributes['in_reply_to']).to be_nil
        expect(message.content_attributes['in_reply_to_external_id']).to eq('ZZZ999')
        expect(message.content_attributes['in_reply_to_snapshot']).to eq(
          'body' => 'an old message', 'author' => contact.name
        )
      end

      it 'stores an empty snapshot when the payload carries no body' do
        conversation

        perform(build_payload(stanza: 'BBB222', reply_to: { 'id' => 'ZZZ999' }))

        message = conversation.reload.messages.last
        expect(message.content_attributes['in_reply_to_external_id']).to eq('ZZZ999')
        expect(message.content_attributes['in_reply_to_snapshot']).to eq({})
      end

      it 'labels quoted media in the snapshot' do
        conversation

        perform(build_payload(stanza: 'BBB222', reply_to: { 'id' => 'ZZZ999', 'hasMedia' => true }))

        message = conversation.reload.messages.last
        expect(message.content_attributes['in_reply_to_snapshot']).to eq('media_type' => 'file')
      end
    end

    context 'when the message is an edit mirror of a message that was itself a reply' do
      it 'quotes the previous version instead of the original reply target' do
        target = create(:message, conversation: conversation, inbox: inbox, account: channel.account,
                                  source_id: 'false_5511888888888@c.us_OLD001')
        original = create(:message, conversation: conversation, inbox: inbox, account: channel.account,
                                    source_id: 'false_5511888888888@c.us_AAA111',
                                    content_attributes: { in_reply_to: target.id, in_reply_to_external_id: target.source_id })

        perform(build_payload(stanza: 'BBB222', reply_to: { 'id' => 'OLD001' }), edited_original: original)

        message = conversation.reload.messages.last
        expect(message.content_attributes['in_reply_to']).to eq(original.id)
        expect(message.content_attributes['in_reply_to_external_id']).to eq(original.source_id)
        expect(message.content_attributes['in_reply_to_snapshot']).to be_nil
      end
    end
  end

  describe 'core vs optional failures' do
    context 'when canonical identity resolution fails (core)' do
      it 'propagates the error and does not create the message' do
        new_lid = '999888777@lid'
        stub_request(:get, "https://waha.test/api/#{channel.session_name}/lids/#{new_lid}")
          .to_return(status: 503, body: '{}', headers: { 'Content-Type' => 'application/json' })

        payload = build_payload(stanza: 'CORE001').merge(
          'from' => new_lid,
          '_data' => { 'Info' => { 'Chat' => new_lid, 'PushName' => 'New Contact' } }
        )

        expect { perform(payload) }.to raise_error(CustomExceptions::Waha::TransientError)
        expect(Message.find_by(source_id: payload['id'])).to be_nil
      end
    end

    context 'when a transient identity-resolution failure clears before the retry' do
      it 'resumes processing and persists exactly one message, not a duplicate' do
        retry_lid = '777666555@lid'
        lookup_url = "https://waha.test/api/#{channel.session_name}/lids/#{retry_lid}"
        payload = build_payload(stanza: 'RETRY001').merge(
          'from' => retry_lid,
          '_data' => { 'Info' => { 'Chat' => retry_lid, 'PushName' => 'Retry Contact' } }
        )

        stub_request(:get, lookup_url)
          .to_return(status: 503, body: '{}', headers: { 'Content-Type' => 'application/json' })
        expect { perform(payload) }.to raise_error(CustomExceptions::Waha::TransientError)
        expect(Message.where(source_id: payload['id']).count).to eq(0)

        stub_request(:get, lookup_url)
          .to_return(status: 200, body: { 'pn' => '5511777666555' }.to_json,
                     headers: { 'Content-Type' => 'application/json' })
        expect { perform(payload) }.not_to raise_error
        expect(Message.where(source_id: payload['id']).count).to eq(1)
      end
    end

    context 'when only the group participant enrichment fails (optional)' do
      it 'still persists the message without the participant enrichment' do
        channel.update!(groups_enabled: true)
        group_jid = '120363000000000000@g.us'
        group_contact = create(:contact, account: channel.account, name: 'Family Group')
        group_contact_inbox = create(:contact_inbox, contact: group_contact, inbox: inbox, source_id: group_jid)
        create(:conversation, account: channel.account, inbox: inbox, contact: group_contact,
                              contact_inbox: group_contact_inbox)

        participant_lid = '444555666@lid'
        stub_request(:get, "https://waha.test/api/#{channel.session_name}/lids/#{participant_lid}")
          .to_return(status: 503, body: '{}', headers: { 'Content-Type' => 'application/json' })

        payload = build_payload(stanza: 'OPT001').merge(
          'from' => group_jid,
          'participant' => participant_lid,
          '_data' => { 'Info' => { 'Chat' => group_jid, 'PushName' => 'Someone' } }
        )

        expect { perform(payload) }.not_to raise_error

        message = Message.find_by!(source_id: payload['id'])
        expect(message.content_attributes['participant_jid']).to eq(participant_lid)
        expect(message.content_attributes['participant_phone']).to be_nil
      end
    end
  end

  describe 'canonical mapping (dual-write)' do
    it 'writes a mapping row alongside the message, scoped to the chat and keyed by the stanza' do
      conversation

      perform(build_payload(stanza: 'BBB222'))

      message = conversation.reload.messages.last
      mapping = WahaMessageMapping.find_by!(message: message)
      expect(mapping).to have_attributes(
        channel_waha_id: channel.id, chat_jid: '5511888888888@c.us', external_id: 'BBB222',
        direction: 'incoming', event_type: 'message', participant_jid: nil
      )
    end

    it 'records the group participant as participant_jid for a group message' do
      channel.update!(groups_enabled: true)
      group_jid = '120363000000000000@g.us'
      group_contact = create(:contact, account: channel.account, name: 'Family Group')
      group_contact_inbox = create(:contact_inbox, contact: group_contact, inbox: inbox, source_id: group_jid)
      create(:conversation, account: channel.account, inbox: inbox, contact: group_contact, contact_inbox: group_contact_inbox)
      participant = '5511777777777@c.us'

      payload = build_payload(stanza: 'GRP001').merge(
        'from' => group_jid, 'participant' => participant,
        '_data' => { 'Info' => { 'Chat' => group_jid, 'PushName' => 'Someone' } }
      )
      perform(payload)

      message = Message.find_by!(source_id: payload['id'])
      mapping = WahaMessageMapping.find_by!(message: message)
      expect(mapping).to have_attributes(chat_jid: group_jid, participant_jid: participant)
    end

    it 'marks an edit mirror with event_type edit' do
      original = create(:message, conversation: conversation, inbox: inbox, account: channel.account,
                                  source_id: 'false_5511888888888@c.us_AAA111')

      perform(build_payload(stanza: 'EDIT01'), edited_original: original)

      mirror = conversation.reload.messages.last
      mapping = WahaMessageMapping.find_by!(message: mirror)
      expect(mapping.event_type).to eq('edit')
    end

    it 'does not persist a second mapping row when the same event is redelivered' do
      conversation
      payload = build_payload(stanza: 'DUP001')

      perform(payload)
      perform(payload)

      message = Message.find_by!(source_id: payload['id'])
      expect(WahaMessageMapping.where(message: message).count).to eq(1)
    end

    it 'still persists the message when the mapping write collides with an existing identity' do
      # A real unique-constraint violation, not a stub: it happens on the same
      # DB connection/transaction as create_message, which is exactly the case
      # a bare rescue can't protect against without a savepoint (see
      # WahaMessageMapping.record!).
      other_message = create(:message, conversation: conversation, inbox: inbox, account: channel.account, source_id: 'unrelated')
      WahaMessageMapping.create!(channel: channel, message: other_message, chat_jid: '5511888888888@c.us',
                                 external_id: 'COLLIDE1', direction: :incoming)

      payload = build_payload(stanza: 'COLLIDE1')
      expect { perform(payload) }.not_to raise_error

      message = Message.find_by!(source_id: payload['id'])
      expect(message).to be_persisted
      expect(WahaMessageMapping.where(chat_jid: '5511888888888@c.us', external_id: 'COLLIDE1').count).to eq(1)
    end
  end

  describe 'media download recovery' do
    let(:media_url) { 'https://waha.test/api/files/abc.jpeg' }

    def media_payload(stanza: 'MEDIA01')
      build_payload(stanza: stanza, body: nil).merge(
        'type' => 'image',
        'hasMedia' => true,
        'media' => { 'url' => 'http://localhost:3000/api/files/abc.jpeg', 'mimetype' => 'image/jpeg' }
      )
    end

    context 'when the media download fails transiently' do
      it 'propagates the error and does not persist an incomplete message' do
        conversation
        stub_request(:get, media_url).to_return(status: 503)
        payload = media_payload

        expect { perform(payload) }.to raise_error(CustomExceptions::Waha::MediaDownloadError)
        expect(Message.find_by(source_id: payload['id'])).to be_nil
      end
    end

    context 'when the transient failure clears before a later attempt' do
      it 'persists exactly one message with its attachment, not a duplicate' do
        conversation
        payload = media_payload
        stub_request(:get, media_url).to_return(status: 503)
        expect { perform(payload) }.to raise_error(CustomExceptions::Waha::MediaDownloadError)
        expect(Message.where(source_id: payload['id']).count).to eq(0)

        stub_request(:get, media_url).to_return(status: 200, body: 'bytes', headers: { 'Content-Type' => 'image/jpeg' })
        expect { perform(payload) }.not_to raise_error

        message = Message.find_by!(source_id: payload['id'])
        expect(message.attachments.size).to eq(1)
        expect(Message.where(source_id: payload['id']).count).to eq(1)
      end
    end

    context 'when the caller already exhausted retries (media_terminal: true)' do
      it 'persists the message with a visible fallback instead of trying the network again' do
        conversation
        payload = media_payload

        described_class.new(channel: channel, payload: payload, media_terminal: true).perform

        expect(a_request(:get, media_url)).not_to have_been_made
        message = Message.find_by!(source_id: payload['id'])
        expect(message.attachments).to be_empty
        expect(message.content_attributes['media_download_failed']).to be(true)
        expect(message.content).to eq(I18n.t('conversations.messages.waha_media_unavailable'))
      end
    end
  end

  describe 'unsupported and invalid payloads' do
    it 'marks an unrecognized GOWS message type as a visible fallback instead of a blank message' do
      conversation

      # A real GOWS poll payload: no body, no media — the content lives entirely
      # under _data.Message.pollCreationMessage, which no converter reads yet
      # (see ticket 20). It must not silently disappear as an empty bubble.
      payload = build_payload(stanza: 'POLL01', body: nil).merge(
        'hasMedia' => false,
        '_data' => {
          'Info' => { 'Chat' => '5511888888888@c.us', 'PushName' => 'John Doe' },
          'Message' => { 'pollCreationMessage' => { 'name' => 'Qual dia é melhor?' } }
        }
      )

      perform(payload)

      message = Message.find_by!(source_id: payload['id'])
      expect(message.content_attributes['is_unsupported']).to be(true)
      expect(message.content).to be_blank
      expect(message.attachments).to be_empty
    end

    it 'marks a declared media type with no media info and no caption as a visible fallback' do
      conversation
      payload = build_payload(stanza: 'BADMEDIA01', body: nil).merge('type' => 'image', 'hasMedia' => false)

      perform(payload)

      message = Message.find_by!(source_id: payload['id'])
      expect(message.content_attributes['is_unsupported']).to be(true)
      expect(message.attachments).to be_empty
    end

    it 'still preserves group participant metadata around an unsupported type' do
      channel.update!(groups_enabled: true)
      group_jid = '120363000000000000@g.us'
      group_contact = create(:contact, account: channel.account, name: 'Family Group')
      group_contact_inbox = create(:contact_inbox, contact: group_contact, inbox: inbox, source_id: group_jid)
      create(:conversation, account: channel.account, inbox: inbox, contact: group_contact, contact_inbox: group_contact_inbox)
      participant = '5511777777777@c.us'

      payload = build_payload(stanza: 'GROUPPOLL01', body: nil).merge(
        'hasMedia' => false,
        'from' => group_jid,
        'participant' => participant,
        '_data' => {
          'Info' => { 'Chat' => group_jid, 'PushName' => 'Someone' },
          'Message' => { 'pollCreationMessage' => { 'name' => 'Qual dia é melhor?' } }
        }
      )

      perform(payload)

      message = Message.find_by!(source_id: payload['id'])
      expect(message.content_attributes['is_unsupported']).to be(true)
      expect(message.content_attributes['participant_jid']).to eq(participant)
    end
  end
end
