require 'rails_helper'

describe Waha::HistoryMessageWriter do
  let(:channel) { create(:channel_waha) }
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: channel.account, name: 'Ana Souza', phone_number: '+5511888888888') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5511888888888@c.us') }
  let(:conversation) do
    create(:conversation, account: channel.account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
  end

  before do
    stub_request(:get, /waha\.test/).to_return(status: 404, body: '{}', headers: { 'Content-Type' => 'application/json' })
  end

  def perform(payload)
    described_class.new(channel: channel, payload: payload, conversation: conversation).perform
    waha_messages(payload['id'], Message.all).first!
  end

  describe 'structured types the payload already carries' do
    it 'attaches a historical location inline, since no later media job would ever fetch it' do
      message = perform(gows_payload('location_static'))

      expect(message.attachments.sole.file_type).to eq('location')
      expect(message.additional_attributes).to include('waha_import_kind' => 'initial', 'imported' => true)
    end

    it 'attaches the original card of a historical shared contact' do
      message = perform(gows_payload('contact_single'))

      expect(message.content).to include('Carlos Lima', '+55 11 3333-2222')
      expect(message.attachments.sole.file.filename.to_s).to eq('contact-1.vcf')
    end

    it 'backdates an event invitation while retaining its converted content' do
      payload = gows_payload('event_creation')
      message = perform(payload)

      expect(message.created_at.to_i).to eq(payload['timestamp'])
      expect(message.content).to include('Reunião de planejamento', 'Sala Aurora')
    end
  end

  describe 'media' do
    it 'leaves the download to Waha::HistoryMediaJob instead of fetching it on the import path' do
      payload = {
        'id' => 'false_5511888888888@c.us_3EB0MEDIA01',
        'timestamp' => 1_757_003_900,
        'from' => '5511888888888@c.us',
        'fromMe' => false,
        'body' => 'olha só',
        'hasMedia' => true,
        'media' => { 'url' => 'https://waha.test/api/files/abc.jpg', 'mimetype' => 'image/jpeg' },
        '_data' => { 'Info' => { 'Chat' => '5511888888888@c.us' }, 'Message' => { 'imageMessage' => { 'mimetype' => 'image/jpeg' } } }
      }

      message = perform(payload)

      expect(message.attachments).to be_empty
      expect(message.content).to eq('olha só')
    end
  end
end
