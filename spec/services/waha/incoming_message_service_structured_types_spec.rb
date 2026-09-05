require 'rails_helper'

# Contract tests for the structured WhatsApp types — location, live location,
# shared contacts (vCard) and replies to a status — driven end to end through
# the observable WAHA seam (payload in, Chatwoot message out) with the
# anonymized GOWS captures in spec/fixtures/waha/gows.
describe Waha::IncomingMessageService do
  let(:channel) { create(:channel_waha) }
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: channel.account, name: 'Ana Souza', phone_number: '+5511888888888') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5511888888888@c.us') }
  let(:conversation) do
    create(:conversation, account: channel.account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
  end

  before do
    conversation
    stub_request(:get, /waha\.test/).to_return(status: 404, body: '{}', headers: { 'Content-Type' => 'application/json' })
  end

  def perform(payload)
    described_class.new(channel: channel, payload: payload).perform
    Message.find_by!(source_id: payload['id'])
  end

  describe 'a static location' do
    it 'lands as a native location attachment with its coordinates and metadata' do
      message = perform(gows_payload('location_static'))
      attachment = message.attachments.sole

      expect(message.content).to be_blank
      expect(message.content_attributes['is_unsupported']).to be_nil
      expect(attachment.file_type).to eq('location')
      expect(attachment.coordinates_lat).to be_within(0.000001).of(-23.550519)
      expect(attachment.coordinates_long).to be_within(0.000001).of(-46.633308)
      expect(attachment.external_url).to eq('https://www.google.com/maps?q=-23.550519,-46.633308')
      expect(attachment.fallback_title).to eq(
        'Padaria Estrela · Rua das Acácias, 100 - São Paulo · te espero aqui · ' \
        'https://padaria-estrela.example.com · -23.550519, -46.633308'
      )
    end
  end

  describe 'a live location' do
    it 'is identified as live and keeps the data the event offered' do
      message = perform(gows_payload('location_live'))
      attachment = message.attachments.sole

      expect(attachment.file_type).to eq('location')
      expect(attachment.fallback_title).to eq('📡 Live location · estou a caminho · -23.561414, -46.655881')
      expect(attachment.coordinates_lat).to be_within(0.000001).of(-23.561414)
    end
  end

  describe 'a location in a group' do
    it 'keeps the structured group sender around the converted type' do
      channel.update!(groups_enabled: true)
      group_contact = create(:contact, account: channel.account, name: 'Family Group')
      group_contact_inbox = create(:contact_inbox, contact: group_contact, inbox: inbox, source_id: '120363000000000000@g.us')
      create(:conversation, account: channel.account, inbox: inbox, contact: group_contact, contact_inbox: group_contact_inbox)
      create(:contact, account: channel.account, name: 'Zé do Grupo', phone_number: '+5511777777777')

      message = perform(gows_payload('location_group'))

      expect(message.content_attributes).to include(
        'sender_name' => 'Zé do Grupo', 'participant_jid' => '5511777777777@c.us', 'participant_phone' => '+5511777777777'
      )
      expect(message.attachments.sole.fallback_title).to eq('Quadra do bairro · -23.5881, -46.6325')
      expect(message.conversation.contact.name).to eq('Family Group')
    end
  end

  describe 'a location with no coordinates' do
    it 'falls back visibly instead of persisting a location with no position' do
      message = perform(gows_payload('location_without_coordinates'))

      expect(message.content_attributes['is_unsupported']).to be(true)
      expect(message.attachments).to be_empty
    end
  end

  describe 'a single shared contact' do
    it 'keeps the name, every phone number and the original card' do
      message = perform(gows_payload('contact_single'))
      attachment = message.attachments.sole

      expect(message.content).to eq("👤 Shared contact\n🪪 Carlos Lima\n📞 +55 11 95555-4444\n📞 +55 11 3333-2222")
      expect(attachment.file_type).to eq('file')
      expect(attachment.file.filename.to_s).to eq('contact-1.vcf')
      expect(attachment.file.download).to include('FN:Carlos Lima')
    end
  end

  describe 'several shared contacts' do
    it 'keeps every card, including one named only by its structured N property' do
      message = perform(gows_payload('contacts_array'))

      expect(message.content).to eq(
        "👤 Shared contacts\n🪪 Carlos Lima\n📞 +55 11 95555-4444\n🪪 Marina Ferreira\n📞 +55 11 94444-3333"
      )
      expect(message.attachments.map { |attachment| attachment.file.filename.to_s }).to eq(%w[contact-1.vcf contact-2.vcf])
    end
  end

  describe 'a shared contact with an empty card' do
    it 'falls back visibly instead of announcing a contact it cannot describe' do
      message = perform(gows_payload('contact_without_vcard'))

      expect(message.content_attributes['is_unsupported']).to be(true)
      expect(message.attachments).to be_empty
    end
  end

  describe 'a reply to a status' do
    it 'keeps the reply text and presents the quoted status as a labelled ghost quote' do
      message = perform(gows_payload('status_reply_text'))

      expect(message.content).to eq('que promoção boa!')
      expect(message.content_attributes['is_status_reply']).to be(true)
      expect(message.content_attributes['in_reply_to']).to be_nil
      expect(message.content_attributes['in_reply_to_external_id']).to eq('3EB0AABBCCDDEEFF0011')
      expect(message.content_attributes['in_reply_to_snapshot']).to eq(
        'body' => 'Frete grátis só hoje', 'author' => '+5511999999999 · Status'
      )
    end

    it 'labels a quoted status photo by its real media type' do
      message = perform(gows_payload('status_reply_image'))

      expect(message.content).to eq('quanto custa esse?')
      expect(message.content_attributes['in_reply_to_snapshot']).to eq(
        'body' => 'Novidades da semana', 'author' => '+5511999999999 · Status', 'media_type' => 'image'
      )
    end
  end
end
