require 'rails_helper'

describe Waha::SendOnWahaService do
  let(:channel) { create(:channel_waha, typing_simulation_enabled: false, auto_read_receipts: false) }
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: channel.account, phone_number: '+5511888888888') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5511888888888@c.us') }
  let(:conversation) do
    create(:conversation, account: channel.account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
  end

  before do
    stub_request(:get, %r{https://waha\.test/api/.+/new-message-id})
      .to_return(status: 200, body: { id: 'GENID001' }.to_json, headers: { 'Content-Type' => 'application/json' })
    stub_request(:get, %r{https://waha\.test/api/.+/chats/.+/messages\?.*})
      .to_return(status: 200, body: [].to_json, headers: { 'Content-Type' => 'application/json' })
    stub_request(:post, 'https://waha.test/api/sendText')
      .to_return(status: 201, body: { id: 'true_5511888888888@c.us_NEW001' }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
  end

  def create_reply(quoted)
    create(:message, conversation: conversation, inbox: inbox, account: channel.account,
                     message_type: :outgoing, content: 'a reply',
                     content_attributes: { in_reply_to: quoted.id, in_reply_to_external_id: quoted.source_id })
  end

  describe '#perform with replyTo' do
    it 'quotes the message source_id in the simple case' do
      quoted = create(:message, conversation: conversation, inbox: inbox, account: channel.account,
                                source_id: 'false_5511888888888@c.us_AAA111')

      described_class.new(message: create_reply(quoted)).perform

      expect(WebMock).to have_requested(:post, 'https://waha.test/api/sendText')
        .with(body: hash_including('reply_to' => quoted.source_id))
    end

    it 'quotes the family anchor when the agent replies to an edit mirror' do
      original = create(:message, conversation: conversation, inbox: inbox, account: channel.account,
                                  source_id: 'false_5511888888888@c.us_AAA111')
      mirror = create(:message, conversation: conversation, inbox: inbox, account: channel.account,
                                source_id: 'false_5511888888888@c.us_EDIT01',
                                additional_attributes: { 'edit_of' => original.source_id })

      described_class.new(message: create_reply(mirror)).perform

      expect(WebMock).to have_requested(:post, 'https://waha.test/api/sendText')
        .with(body: hash_including('reply_to' => original.source_id))
    end

    it 'quotes the first confirmed part of a multipart message' do
      quoted = create(:message, conversation: conversation, inbox: inbox, account: channel.account,
                                source_id: 'true_5511888888888@c.us_FIRST')
      attempt = WahaDeliveryAttempt.create!(channel: channel, message: quoted, chat_jid: contact_inbox.source_id, status: :sent)
      attempt.delivery_parts.create!(position: 0, part_type: :text, status: :sent,
                                     source_id: 'true_5511888888888@c.us_FIRST', external_id: 'FIRST')
      attempt.delivery_parts.create!(position: 1, part_type: :text, status: :sent,
                                     source_id: 'true_5511888888888@c.us_SECOND', external_id: 'SECOND')

      described_class.new(message: create_reply(quoted)).perform

      expect(WebMock).to have_requested(:post, 'https://waha.test/api/sendText')
        .with(body: hash_including('reply_to' => 'true_5511888888888@c.us_FIRST'))
    end

    it 'sends no replyTo when the message is not a reply' do
      message = create(:message, conversation: conversation, inbox: inbox, account: channel.account,
                                 message_type: :outgoing, content: 'plain text')

      described_class.new(message: message).perform

      expect(WebMock).to(have_requested(:post, 'https://waha.test/api/sendText')
        .with { |request| !JSON.parse(request.body).key?('reply_to') })
    end
  end

  describe '#perform with mentions' do
    let(:channel) do
      create(:channel_waha, groups_enabled: true, typing_simulation_enabled: false, auto_read_receipts: false)
    end
    let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '120363012345678901@g.us') }

    it 'sends phone, LID, and collective mentions in the GOWS payload without changing the stored body' do
      content = '@all Ping @5511999999999 and @1144444444444444@lid'
      message = create(:message, conversation: conversation, inbox: inbox, account: channel.account,
                                 message_type: :outgoing, content: content)

      described_class.new(message: message).perform

      request_matcher = have_requested(:post, 'https://waha.test/api/sendText').with do |request|
        payload = JSON.parse(request.body)
        payload['text'] == 'Ping @5511999999999 and @1144444444444444' &&
          payload['mentions'] == ['all', '1144444444444444@lid', '5511999999999@c.us']
      end
      expect(WebMock).to request_matcher
      expect(message.reload.content).to eq(content)
    end

    it 'deduplicates structured recipients and leaves unknown references readable' do
      message = create(:message, conversation: conversation, inbox: inbox, account: channel.account,
                                 message_type: :outgoing,
                                 content: 'Ping @5511999999999, @5511999999999, @someone, @12345 and @1234567@unknown')

      described_class.new(message: message).perform

      request_matcher = have_requested(:post, 'https://waha.test/api/sendText').with do |request|
        payload = JSON.parse(request.body)
        payload['text'] == message.content && payload['mentions'] == ['5511999999999@c.us']
      end
      expect(WebMock).to request_matcher
    end

    it 'adds mentions to supported media captions' do
      message = create(:message, conversation: conversation, inbox: inbox, account: channel.account,
                                 message_type: :outgoing, content: 'Ping @5511999999999')
      attachment = message.attachments.create!(account: channel.account, file_type: :image,
                                               file: fixture_file_upload(Rails.root.join('spec/assets/sample.png'), 'image/png'))
      allow(attachment).to receive(:download_url).and_return('https://chatwoot.test/image.png')
      stub_request(:post, 'https://waha.test/api/sendImage')
        .to_return(status: 201, body: { id: 'true_120363012345678901@g.us_NEW002' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      described_class.new(message: message).perform

      expect(WebMock).to have_requested(:post, 'https://waha.test/api/sendImage')
        .with(body: hash_including('caption' => message.content, 'mentions' => ['5511999999999@c.us']))
    end

    it 'keeps voice payloads unchanged because GOWS does not accept mentions on sendVoice' do
      message = create(:message, conversation: conversation, inbox: inbox, account: channel.account,
                                 message_type: :outgoing, content: 'Ping @5511999999999')
      attachment = message.attachments.create!(account: channel.account, file_type: :audio,
                                               file: fixture_file_upload(Rails.root.join('spec/assets/sample.ogg'), 'audio/ogg'))
      allow(attachment).to receive(:download_url).and_return('https://chatwoot.test/audio.ogg')
      stub_request(:post, 'https://waha.test/api/sendVoice')
        .to_return(status: 201, body: { id: 'true_120363012345678901@g.us_NEW003' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      described_class.new(message: message).perform

      request_matcher = have_requested(:post, 'https://waha.test/api/sendVoice').with do |request|
        !JSON.parse(request.body).key?('mentions')
      end
      expect(WebMock).to request_matcher
    end

    it 'does not send collective or participant mentions in a direct chat' do
      direct_contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5511888888888@c.us')
      direct_conversation = create(:conversation, account: channel.account, inbox: inbox, contact: contact,
                                                  contact_inbox: direct_contact_inbox)
      message = create(:message, conversation: direct_conversation, inbox: inbox, account: channel.account,
                                 message_type: :outgoing, content: '@all Ping @5511999999999')

      described_class.new(message: message).perform

      request_matcher = have_requested(:post, 'https://waha.test/api/sendText').with do |request|
        payload = JSON.parse(request.body)
        payload['text'] == message.content && !payload.key?('mentions')
      end
      expect(WebMock).to request_matcher
    end

    it 'keeps a group reply without mentions unchanged' do
      quoted = create(:message, conversation: conversation, inbox: inbox, account: channel.account,
                                source_id: 'false_120363012345678901@g.us_AAA111')
      message = create_reply(quoted)

      described_class.new(message: message).perform

      request_matcher = have_requested(:post, 'https://waha.test/api/sendText').with do |request|
        payload = JSON.parse(request.body)
        payload['text'] == 'a reply' && payload['reply_to'] == quoted.source_id && !payload.key?('mentions')
      end
      expect(WebMock).to request_matcher
    end
  end

  describe '#perform delivery outcomes' do
    # Isolates these examples from typing-simulation/read-receipt presence calls
    # (Redis-backed, exercised separately) so only the send/HTTP seam is under test.
    let(:channel) { create(:channel_waha, typing_simulation_enabled: false, auto_read_receipts: false) }

    let(:message) do
      create(:message, conversation: conversation, inbox: inbox, account: channel.account,
                       message_type: :outgoing, content: 'hello')
    end

    it 'persists the WAHA id on a successful send' do
      described_class.new(message: message).perform

      expect(message.reload).to have_attributes(status: 'sent', source_id: 'true_5511888888888@c.us_NEW001')
    end

    it 'dual-writes a canonical mapping row keyed by the chat and the stanza' do
      described_class.new(message: message).perform

      mapping = WahaMessageMapping.find_by!(message: message)
      expect(mapping).to have_attributes(
        channel_waha_id: channel.id, chat_jid: '5511888888888@c.us', external_id: 'NEW001',
        direction: 'outgoing', event_type: 'message', participant_jid: nil
      )
    end

    it 'marks the message failed without a source_id on a definitive (4xx) error' do
      stub_request(:post, 'https://waha.test/api/sendText')
        .to_return(status: 422, body: { message: 'invalid chatId' }.to_json, headers: { 'Content-Type' => 'application/json' })

      described_class.new(message: message).perform

      expect(message.reload).to have_attributes(status: 'failed', source_id: nil)
      expect(message.external_error).to include('422')
      expect(WahaDeliveryAttempt.find_by(message: message).status).to eq('failed')
    end

    it 'schedules a limited retry through Waha::DeliverJob on a transient (5xx) error' do
      stub_request(:post, 'https://waha.test/api/sendText')
        .to_return(status: 503, body: { message: 'session not ready' }.to_json, headers: { 'Content-Type' => 'application/json' })

      expect { described_class.new(message: message).perform }
        .to have_enqueued_job(Waha::DeliverJob).with(message.id)

      expect(message.reload).to have_attributes(status: 'sent', source_id: nil)
      expect(WahaDeliveryAttempt.find_by(message: message)).to have_attributes(status: 'pending', attempt_count: 1)
    end

    it 'recovers on a retry without creating a second message' do
      message # force creation before measuring Message.count
      stub_request(:post, 'https://waha.test/api/sendText').to_return(
        { status: 503, body: { message: 'down' }.to_json, headers: { 'Content-Type' => 'application/json' } },
        { status: 201, body: { id: 'true_5511888888888@c.us_RETRY1' }.to_json, headers: { 'Content-Type' => 'application/json' } }
      )

      expect do
        described_class.new(message: message).perform
        # Simulates Waha::DeliverJob firing the scheduled retry: it re-reads the
        # persisted attempt from the DB rather than being told which try this is.
        described_class.new(message: message, skip_presence: true).perform
      end.not_to change(Message, :count)

      expect(message.reload).to have_attributes(status: 'sent', source_id: 'true_5511888888888@c.us_RETRY1')
      expect(WahaMessageMapping.where(message: message).count).to eq(1)
      expect(WahaDeliveryAttempt.find_by(message: message)).to have_attributes(status: 'sent', attempt_count: 2)
    end

    it 'marks the message failed with no fake source_id after exhausting retries' do
      stub_request(:post, 'https://waha.test/api/sendText')
        .to_return(status: 503, body: { message: 'down' }.to_json, headers: { 'Content-Type' => 'application/json' })
      WahaDeliveryAttempt.create!(channel: channel, message: message, chat_jid: '5511888888888@c.us',
                                  status: :pending, attempt_count: Waha::SendOnWahaService::MAX_SEND_ATTEMPTS - 1)

      Waha::DeliverJob.perform_now(message.id)

      expect(message.reload).to have_attributes(status: 'failed', source_id: nil)
      expect(WahaDeliveryAttempt.find_by(message: message).status).to eq('failed')
    end

    it 'marks the message failed when WAHA responds success with no message id' do
      stub_request(:post, 'https://waha.test/api/sendText')
        .to_return(status: 200, body: {}.to_json, headers: { 'Content-Type' => 'application/json' })

      described_class.new(message: message).perform

      expect(message.reload).to have_attributes(status: 'failed', source_id: nil)
    end

    it 'does not call WAHA a second time when another execution already claimed the attempt' do
      WahaDeliveryAttempt.create!(channel: channel, message: message, chat_jid: '5511888888888@c.us', status: :sending)

      Waha::DeliverJob.perform_now(message.id)

      expect(a_request(:post, 'https://waha.test/api/sendText')).not_to have_been_made
      expect(message.reload).to have_attributes(source_id: nil)
    end

    it 'sends input_csat text (with the survey link) through the same text contract instead of dropping it' do
      csat_message = create(:message, conversation: conversation, inbox: inbox, account: channel.account,
                                      message_type: :template, content_type: :input_csat, content: 'Rate us')

      described_class.new(message: csat_message).perform

      # outgoing_content (MessageContentPresenter) is what makes this a survey
      # link rather than the raw stored content — the same mechanism every other
      # non-web-widget channel already uses for input_csat.
      expect(WebMock).to(have_requested(:post, 'https://waha.test/api/sendText')
        .with { |request| JSON.parse(request.body)['text'].include?("/survey/responses/#{conversation.uuid}") })
      expect(csat_message.reload.source_id).to eq('true_5511888888888@c.us_NEW001')
    end

    describe 'the pre-generated id' do
      it "sends WAHA's pre-generated id as the request's id" do
        described_class.new(message: message).perform

        expect(WebMock).to have_requested(:post, 'https://waha.test/api/sendText')
          .with(body: hash_including('id' => 'GENID001'))
        expect(WahaDeliveryAttempt.find_by(message: message).client_message_id).to eq('GENID001')
      end

      it 'sends without an id, and keeps working, when the engine does not support pre-generated ids' do
        stub_request(:get, %r{https://waha\.test/api/.+/new-message-id})
          .to_return(status: 404, body: { message: 'not implemented' }.to_json, headers: { 'Content-Type' => 'application/json' })

        described_class.new(message: message).perform

        expect(WebMock).to(have_requested(:post, 'https://waha.test/api/sendText')
          .with { |request| !JSON.parse(request.body).key?('id') })
        expect(message.reload).to have_attributes(status: 'sent', source_id: 'true_5511888888888@c.us_NEW001')
      end
    end

    describe 'reconciliation after a lost response' do
      it 'adopts the message WAHA already sent instead of resending when the HTTP response never arrives' do
        stub_request(:post, 'https://waha.test/api/sendText').to_timeout
        stub_request(:get, %r{https://waha\.test/api/.+/chats/.+/messages\?.*})
          .to_return(status: 200, body: [{ id: 'true_5511888888888@c.us_GENID001' }].to_json,
                     headers: { 'Content-Type' => 'application/json' })

        expect { described_class.new(message: message).perform }
          .not_to have_enqueued_job(Waha::DeliverJob)

        expect(a_request(:post, 'https://waha.test/api/sendText')).to have_been_made.once
        expect(message.reload).to have_attributes(status: 'sent', source_id: 'true_5511888888888@c.us_GENID001')
        expect(WahaMessageMapping.where(message: message).count).to eq(1)
        expect(WahaDeliveryAttempt.find_by(message: message).status).to eq('sent')
      end

      it 'retries normally when reconciliation finds no matching message' do
        stub_request(:post, 'https://waha.test/api/sendText').to_timeout

        expect { described_class.new(message: message).perform }
          .to have_enqueued_job(Waha::DeliverJob).with(message.id)

        expect(message.reload.source_id).to be_nil
      end
    end
  end

  describe '#perform multipart delivery' do
    let(:message) do
      create(:message, conversation: conversation, inbox: inbox, account: channel.account,
                       message_type: :outgoing, content: 'hello with files')
    end
    let!(:image) do
      message.attachments.create!(account: channel.account, file_type: :image,
                                  file: fixture_file_upload(Rails.root.join('spec/assets/sample.png'), 'image/png'))
    end
    let!(:document) do
      message.attachments.create!(account: channel.account, file_type: :file,
                                  file: fixture_file_upload(Rails.root.join('spec/assets/sample.pdf'), 'application/pdf'))
    end

    before do
      allow(image).to receive(:download_url).and_return('https://chatwoot.test/image.png')
      allow(document).to receive(:download_url).and_return('https://chatwoot.test/sample.pdf')
      stub_request(:get, %r{https://waha\.test/api/.+/new-message-id}).to_return(
        { status: 200, body: { id: 'PART-TEXT' }.to_json, headers: { 'Content-Type' => 'application/json' } },
        { status: 200, body: { id: 'PART-IMAGE' }.to_json, headers: { 'Content-Type' => 'application/json' } },
        { status: 200, body: { id: 'PART-FILE' }.to_json, headers: { 'Content-Type' => 'application/json' } }
      )
    end

    it 'sends text then every eligible attachment and checkpoints each part in that order' do
      dispatch_order = []
      stub_request(:post, 'https://waha.test/api/sendText').to_return do
        dispatch_order << :text
        { status: 201, body: { id: 'true_5511888888888@c.us_TEXT-1' }.to_json,
          headers: { 'Content-Type' => 'application/json' } }
      end
      stub_request(:post, 'https://waha.test/api/sendImage').to_return do
        dispatch_order << :image
        { status: 201, body: { id: 'true_5511888888888@c.us_IMAGE-2' }.to_json,
          headers: { 'Content-Type' => 'application/json' } }
      end
      stub_request(:post, 'https://waha.test/api/sendFile').to_return do
        dispatch_order << :file
        { status: 201, body: { id: 'true_5511888888888@c.us_FILE-3' }.to_json,
          headers: { 'Content-Type' => 'application/json' } }
      end

      described_class.new(message: message).perform

      attempt = WahaDeliveryAttempt.find_by!(message: message)
      expect(dispatch_order).to eq(%i[text image file])
      expect(attempt).to have_attributes(status: 'sent', external_id: 'TEXT-1')
      expect(attempt.delivery_parts.in_delivery_order.pluck(:position, :part_type, :status, :client_message_id, :external_id)).to eq(
        [[0, 'text', 'sent', 'PART-TEXT', 'TEXT-1'],
         [1, 'attachment', 'sent', 'PART-IMAGE', 'IMAGE-2'],
         [2, 'attachment', 'sent', 'PART-FILE', 'FILE-3']]
      )
      expect(WahaMessageMapping.where(message: message).order(:part).pluck(:part, :external_id)).to eq(
        [[0, 'TEXT-1'], [1, 'IMAGE-2'], [2, 'FILE-3']]
      )
      expect(message.reload.source_id).to eq('true_5511888888888@c.us_TEXT-1')
    end

    it 'resumes at the failed part without resending confirmed text' do
      stub_request(:post, 'https://waha.test/api/sendText')
        .to_return(status: 201, body: { id: 'true_5511888888888@c.us_TEXT-1' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
      stub_request(:post, 'https://waha.test/api/sendImage').to_return(
        { status: 503, body: { message: 'temporarily unavailable' }.to_json, headers: { 'Content-Type' => 'application/json' } },
        { status: 201, body: { id: 'true_5511888888888@c.us_IMAGE-2' }.to_json,
          headers: { 'Content-Type' => 'application/json' } }
      )
      stub_request(:post, 'https://waha.test/api/sendFile')
        .to_return(status: 201, body: { id: 'true_5511888888888@c.us_FILE-3' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      expect { described_class.new(message: message).perform }.to have_enqueued_job(Waha::DeliverJob).with(message.id)

      attempt = WahaDeliveryAttempt.find_by!(message: message)
      expect(attempt).to have_attributes(status: 'pending', attempt_count: 1, last_error: include('503'))
      expect(attempt.delivery_parts.in_delivery_order.pluck(:status)).to eq(%w[sent pending pending])

      Waha::DeliverJob.perform_now(message.id)

      expect(a_request(:post, 'https://waha.test/api/sendText')).to have_been_made.once
      expect(a_request(:post, 'https://waha.test/api/sendImage')).to have_been_made.twice
      expect(a_request(:post, 'https://waha.test/api/sendFile')).to have_been_made.once
      expect(attempt.reload).to have_attributes(status: 'sent', attempt_count: 2, last_error: nil)
    end

    it 'keeps an exhausted partial failure visible and resumable by a manual retry' do
      stub_request(:post, 'https://waha.test/api/sendText')
        .to_return(status: 201, body: { id: 'true_5511888888888@c.us_TEXT-1' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
      stub_request(:post, 'https://waha.test/api/sendImage').to_return(
        { status: 503, body: { message: 'temporarily unavailable' }.to_json, headers: { 'Content-Type' => 'application/json' } },
        { status: 503, body: { message: 'still unavailable' }.to_json, headers: { 'Content-Type' => 'application/json' } },
        { status: 201, body: { id: 'true_5511888888888@c.us_IMAGE-2' }.to_json,
          headers: { 'Content-Type' => 'application/json' } }
      )
      stub_request(:post, 'https://waha.test/api/sendFile')
        .to_return(status: 201, body: { id: 'true_5511888888888@c.us_FILE-3' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      described_class.new(message: message).perform
      attempt = WahaDeliveryAttempt.find_by!(message: message)
      attempt.update!(attempt_count: described_class::MAX_SEND_ATTEMPTS - 1)
      described_class.new(message: message, skip_presence: true).perform

      expect(message.reload).to have_attributes(status: 'failed', source_id: 'true_5511888888888@c.us_TEXT-1')
      expect(attempt.reload).to have_attributes(status: 'failed', last_error: include('503'))
      expect(attempt.delivery_parts.in_delivery_order.pluck(:status)).to eq(%w[sent pending pending])

      Waha::DeliverJob.perform_now(message.id)

      expect(a_request(:post, 'https://waha.test/api/sendText')).to have_been_made.once
      expect(attempt.reload.status).to eq('sent')
      expect(message.reload).to have_attributes(status: 'sent', external_error: nil)
    end

    it 'keeps a single attachment with text as one captioned WhatsApp message' do
      document.destroy!
      stub_request(:get, %r{https://waha\.test/api/.+/new-message-id})
        .to_return(status: 200, body: { id: 'ONLY-IMAGE' }.to_json, headers: { 'Content-Type' => 'application/json' })
      stub_request(:post, 'https://waha.test/api/sendImage')
        .to_return(status: 201, body: { id: 'true_5511888888888@c.us_ONLY-IMAGE' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      described_class.new(message: message.reload).perform

      expect(a_request(:post, 'https://waha.test/api/sendText')).not_to have_been_made
      expect(WebMock).to have_requested(:post, 'https://waha.test/api/sendImage')
        .with(body: hash_including('caption' => 'hello with files', 'id' => 'ONLY-IMAGE'))
      expect(WahaDeliveryAttempt.find_by!(message: message).delivery_parts.count).to eq(1)
    end
  end
end
