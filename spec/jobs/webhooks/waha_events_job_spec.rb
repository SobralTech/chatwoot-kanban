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

      expect(Message.find_by(source_id: params['payload']['id'])).to be_nil
    end

    it 'creates exactly one message with its attachment once the download recovers, with no duplicate on redelivery' do
      conversation
      params = media_message_params
      stub_request(:get, media_url).to_return(status: 503)
      described_class.perform_now(channel.id, params)
      expect(Message.where(source_id: params['payload']['id']).count).to eq(0)

      stub_request(:get, media_url).to_return(status: 200, body: 'bytes', headers: { 'Content-Type' => 'image/jpeg' })
      described_class.perform_now(channel.id, params, 0, 2)

      message = Message.find_by!(source_id: params['payload']['id'])
      expect(message.attachments.size).to eq(1)

      # WAHA (or Sidekiq) redelivering the same event afterwards must not duplicate it.
      described_class.perform_now(channel.id, params, 0, 2)
      expect(Message.where(source_id: params['payload']['id']).count).to eq(1)
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
      message = Message.find_by!(source_id: params['payload']['id'])
      expect(message.attachments).to be_empty
      expect(message.content_attributes['media_download_failed']).to be(true)
      expect(message.content).to eq(I18n.t('conversations.messages.waha_media_unavailable'))
    end
  end
end
