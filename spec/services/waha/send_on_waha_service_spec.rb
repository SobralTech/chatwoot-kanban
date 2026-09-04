require 'rails_helper'

describe Waha::SendOnWahaService do
  let(:channel) { create(:channel_waha) }
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: channel.account, phone_number: '+5511888888888') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5511888888888@c.us') }
  let(:conversation) do
    create(:conversation, account: channel.account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
  end

  before do
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

    it 'sends no replyTo when the message is not a reply' do
      message = create(:message, conversation: conversation, inbox: inbox, account: channel.account,
                                 message_type: :outgoing, content: 'plain text')

      described_class.new(message: message).perform

      expect(WebMock).to(have_requested(:post, 'https://waha.test/api/sendText')
        .with { |request| !JSON.parse(request.body).key?('reply_to') })
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
    end

    it 'schedules a limited retry through Waha::DeliverJob on a transient (5xx) error' do
      stub_request(:post, 'https://waha.test/api/sendText')
        .to_return(status: 503, body: { message: 'session not ready' }.to_json, headers: { 'Content-Type' => 'application/json' })

      expect { described_class.new(message: message).perform }
        .to have_enqueued_job(Waha::DeliverJob).with(message.id, 2)

      expect(message.reload).to have_attributes(status: 'sent', source_id: nil)
    end

    it 'recovers on a retry without creating a second message' do
      message # force creation before measuring Message.count
      stub_request(:post, 'https://waha.test/api/sendText').to_return(
        { status: 503, body: { message: 'down' }.to_json, headers: { 'Content-Type' => 'application/json' } },
        { status: 201, body: { id: 'true_5511888888888@c.us_RETRY1' }.to_json, headers: { 'Content-Type' => 'application/json' } }
      )

      expect do
        described_class.new(message: message).perform
        described_class.new(message: message, skip_presence: true, attempt: 2).perform
      end.not_to change(Message, :count)

      expect(message.reload).to have_attributes(status: 'sent', source_id: 'true_5511888888888@c.us_RETRY1')
      expect(WahaMessageMapping.where(message: message).count).to eq(1)
    end

    it 'marks the message failed with no fake source_id after exhausting retries' do
      stub_request(:post, 'https://waha.test/api/sendText')
        .to_return(status: 503, body: { message: 'down' }.to_json, headers: { 'Content-Type' => 'application/json' })

      described_class.new(message: message, skip_presence: true, attempt: Waha::SendOnWahaService::MAX_SEND_ATTEMPTS).perform

      expect(message.reload).to have_attributes(status: 'failed', source_id: nil)
    end

    it 'marks the message failed when WAHA responds success with no message id' do
      stub_request(:post, 'https://waha.test/api/sendText')
        .to_return(status: 200, body: {}.to_json, headers: { 'Content-Type' => 'application/json' })

      described_class.new(message: message).perform

      expect(message.reload).to have_attributes(status: 'failed', source_id: nil)
    end
  end
end
