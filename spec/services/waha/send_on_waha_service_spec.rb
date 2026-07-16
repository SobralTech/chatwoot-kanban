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
end
