require 'rails_helper'

# Contract tests for Pix, Facebook/Instagram ad replies and albums — driven end
# to end through the observable WAHA seam (payload in, Chatwoot message out)
# with the anonymized GOWS captures in spec/fixtures/waha/gows.
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

  describe 'a Pix payment request' do
    it 'keeps the merchant, key, amount and reference without exposing the raw button payload' do
      message = perform(gows_payload('pix_payment'))

      expect(message.content).to eq(
        "💰 Pix payment\nMerchant: Padaria Estrela\nPix key: contato@padariaestrela.example.com (EMAIL)\n" \
        "Amount: 45.90 BRL\nReference: PEDIDO-4821"
      )
      expect(message.content_attributes['pix']).to eq(
        'merchant_name' => 'Padaria Estrela', 'key' => 'contato@padariaestrela.example.com', 'key_type' => 'EMAIL',
        'amount' => '45.90 BRL', 'reference_id' => 'PEDIDO-4821'
      )
      expect(message.attachments).to be_empty
    end
  end

  describe 'a Pix button with no usable key' do
    it 'falls back visibly instead of announcing a payment it cannot describe' do
      payload = gows_payload('pix_payment')
      button = payload.dig('_data', 'Message', 'interactiveMessage', 'interactiveMessage', 'nativeFlowMessage', 'buttons').first
      button['buttonParamsJSON'] = '{"payment_settings":[]}'

      message = perform(payload)

      expect(message.content_attributes['is_unsupported']).to be(true)
    end
  end

  describe 'a Facebook ad reply with the contact\'s own text' do
    it 'keeps the typed reply as the message content and the ad as metadata' do
      message = perform(gows_payload('facebook_ad_reply'))

      expect(message.content).to eq('Olá! Vi o anúncio e queria saber mais.')
      expect(message.content_attributes['facebook_ad']).to eq(
        'title' => 'Promoção de inverno', 'body' => 'Peças selecionadas com até 40% de desconto',
        'media_url' => 'https://cdn.example.com/ads/inverno.jpg', 'source_url' => 'https://www.facebook.com/ads/inverno'
      )
      expect(message.content_attributes['is_unsupported']).to be_nil
    end
  end

  describe 'a Facebook ad reply with no typed text' do
    it 'renders the ad itself as visible content instead of a generic unsupported bubble' do
      payload = gows_payload('facebook_ad_reply', 'body' => nil)
      payload.dig('_data', 'Message', 'extendedTextMessage')['text'] = nil

      message = perform(payload)

      expect(message.content).to eq(
        "📣 Facebook/Instagram ad\nPromoção de inverno\nPeças selecionadas com até 40% de desconto\n" \
        "Media: https://cdn.example.com/ads/inverno.jpg\nSource: https://www.facebook.com/ads/inverno"
      )
      expect(message.content_attributes['is_unsupported']).to be_nil
      expect(message.content_attributes['facebook_ad']).to be_present
    end
  end

  describe 'an album' do
    before do
      stub_request(:get, 'https://waha.test/api/files/album-photo-1.jpg')
        .to_return(status: 200, body: 'photo-1-bytes', headers: { 'Content-Type' => 'image/jpeg' })
      stub_request(:get, 'https://waha.test/api/files/album-photo-2.jpg').to_return(status: 404)
      stub_request(:get, 'https://waha.test/api/files/album-video-1.mp4')
        .to_return(status: 200, body: 'video-1-bytes', headers: { 'Content-Type' => 'video/mp4' })

      # Memoize in creation order: the header must exist before its parts.
      header
      photo1
      photo2
      video
    end

    let(:header) { perform(gows_payload('album_header')) }
    let(:photo1) { perform(gows_payload('album_item_image_1')) }
    let(:photo2) { perform(gows_payload('album_item_image_2')) }
    let(:video) { perform(gows_payload('album_item_video')) }
    let(:album_id) { Waha::Anchoring.stanza_of(header.source_id) }

    it 'renders the header with the expected photo and video counts' do
      expect(header.content).to eq('🖼️ Album · 2 photos, 1 video')
      expect(header.content_attributes['album']).to eq('expected_image_count' => 2, 'expected_video_count' => 1)
    end

    it 'tags every photo and video back to the header' do
      expect([photo1, photo2, video].map { |message| message.content_attributes['album_id'] }).to all(eq(album_id))
    end

    it 'keeps a confirmed part\'s attachment even though a sibling failed' do
      expect(photo1.attachments.sole.file_type).to eq('image')
      expect(photo1.content_attributes['media_download_failed']).to be_nil
      expect(video.attachments.sole.file_type).to eq('video')
      expect(video.content_attributes['media_download_failed']).to be_nil
    end

    it 'marks the failed part visibly instead of hiding it or blocking the others' do
      expect(photo2.attachments).to be_empty
      expect(photo2.content_attributes['media_download_failed']).to be(true)
      expect(photo2.content).to eq(I18n.t('conversations.messages.waha_media_unavailable'))
    end

    it 'keeps the conversation\'s message order matching the order the parts were sent' do
      ordered_ids = conversation.messages.order(:created_at).pluck(:id)
      expect(ordered_ids).to eq([header.id, photo1.id, photo2.id, video.id])
    end
  end

  describe 'an album header with no expected media' do
    it 'falls back visibly instead of announcing an empty album' do
      payload = { 'id' => 'false_5511888888888@c.us_ALBUMEMPTY01', 'fromMe' => false, 'from' => '5511888888888@c.us',
                  'timestamp' => 1_757_100_700,
                  '_data' => { 'Info' => { 'Chat' => '5511888888888@c.us' },
                               'Message' => { 'albumMessage' => { 'expectedImageCount' => 0, 'expectedVideoCount' => 0 } } } }

      message = perform(payload)

      expect(message.content_attributes['is_unsupported']).to be(true)
    end
  end
end
