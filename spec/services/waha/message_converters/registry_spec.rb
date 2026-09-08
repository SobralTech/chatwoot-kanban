require 'rails_helper'

# Contract tests for the converter registry: given a WAHA payload, it must
# select a converter that keeps the already-supported types working exactly
# as before, and must never let an unrecognized or malformed payload resolve
# to "nothing" (no content, no attachment, no visible marker).
#
# The structured types are driven by the anonymized GOWS captures in
# spec/fixtures/waha/gows — see the README there for the field-casing contract.
describe Waha::MessageConverters::Registry do
  let(:channel) { build_stubbed(:channel_waha) }

  def text_payload(body: 'Oi, tudo bem?')
    { 'id' => 'x', 'body' => body, 'hasMedia' => false, 'type' => 'chat' }
  end

  def media_payload(kind:, mimetype: 'image/jpeg')
    {
      'id' => 'x',
      'body' => nil,
      'type' => kind,
      'hasMedia' => true,
      'media' => { 'url' => 'http://localhost:3000/api/files/abc', 'mimetype' => mimetype }
    }
  end

  def historical_media_payload(kind:, body: nil)
    node_key = { 'image' => 'imageMessage', 'video' => 'videoMessage', 'audio' => 'audioMessage' }.fetch(kind)
    mimetype = { 'image' => 'image/jpeg', 'video' => 'video/mp4', 'audio' => 'audio/ogg' }.fetch(kind)

    {
      'id' => "false_5511888888888@c.us_HISTORY_#{kind}",
      'body' => body,
      'type' => kind,
      'hasMedia' => true,
      'media' => { 'mimetype' => mimetype },
      '_data' => {
        'Info' => { 'Chat' => '5511888888888@c.us', 'MediaType' => kind },
        'Message' => { node_key => { 'mimetype' => mimetype } }
      }
    }
  end

  def poll_payload
    gows_payload('poll_creation')
  end

  def converter_for(payload = nil, defer_media: false, **keyword_payload)
    payload ||= keyword_payload
    described_class.for(channel: channel, payload: payload, defer_media: defer_media)
  end

  describe '.for' do
    Waha::MediaAttacher::MEDIA_KINDS.each do |kind|
      it "selects the media converter for a #{kind} payload" do
        expect(converter_for(media_payload(kind: kind))).to be_a(Waha::MessageConverters::Media)
      end
    end

    %w[image video audio].each do |kind|
      it "selects pending media for a historical #{kind} without a URL" do
        converter = converter_for(historical_media_payload(kind: kind), defer_media: true)

        expect(converter).to be_a(Waha::MessageConverters::Media)
        expect(converter.metadata).to eq(
          media_download_pending: true,
          media_download_provenance: 'waha_history',
          media_download_content: 'waha_media_pending'
        )
        expect(converter.metadata).not_to have_key(:is_unsupported)
      end
    end

    it 'selects the text converter for a plain text payload' do
      expect(converter_for(text_payload)).to be_a(Waha::MessageConverters::Text)
    end

    it 'selects the poll converter for a GOWS poll creation' do
      expect(converter_for(poll_payload)).to be_a(Waha::MessageConverters::Poll)
    end

    it 'selects the fallback converter for a declared media type with no media info and no caption' do
      expect(converter_for('id' => 'x', 'type' => 'image', 'hasMedia' => false)).to be_a(Waha::MessageConverters::Fallback)
    end

    it 'prefers text over the fallback when an unrecognized payload still carries a body' do
      expect(converter_for('id' => 'x', 'hasMedia' => false, 'body' => 'texto qualquer')).to be_a(Waha::MessageConverters::Text)
    end

    %w[location_static location_live location_group].each do |fixture|
      it "selects the location converter for the #{fixture} GOWS payload" do
        expect(converter_for(gows_payload(fixture))).to be_a(Waha::MessageConverters::Location)
      end
    end

    %w[contact_single contacts_array].each do |fixture|
      it "selects the vCard converter for the #{fixture} GOWS payload" do
        expect(converter_for(gows_payload(fixture))).to be_a(Waha::MessageConverters::VCard)
      end
    end

    %w[list_creation list_selection].each do |fixture|
      it "selects the list converter for the #{fixture} GOWS payload" do
        expect(converter_for(gows_payload(fixture))).to be_a(Waha::MessageConverters::List)
      end
    end

    it 'selects the event converter for a GOWS event invitation' do
      expect(converter_for(gows_payload('event_creation'))).to be_a(Waha::MessageConverters::Event)
    end

    it 'selects the Pix converter for a GOWS Pix payment request' do
      expect(converter_for(gows_payload('pix_payment'))).to be_a(Waha::MessageConverters::Pix)
    end

    it 'selects the album converter for a GOWS album header' do
      expect(converter_for(gows_payload('album_header'))).to be_a(Waha::MessageConverters::Album)
    end

    it 'wraps the text converter in FacebookAd for a click-to-WhatsApp ad reply' do
      converter = converter_for(gows_payload('facebook_ad_reply'))

      expect(converter).to be_a(Waha::MessageConverters::FacebookAd)
      expect(converter.content).to eq('Olá! Vi o anúncio e queria saber mais.')
    end

    it 'wraps the media converter in AlbumItem for one photo of an album' do
      expect(converter_for(gows_payload('album_item_image_1'))).to be_a(Waha::MessageConverters::AlbumItem)
    end

    %w[status_reply_text status_reply_image].each do |fixture|
      it "selects the status reply converter for the #{fixture} GOWS payload" do
        expect(converter_for(gows_payload(fixture))).to be_a(Waha::MessageConverters::StatusReply)
      end
    end

    it 'reads a location from WAHA\'s engine-agnostic top-level field when the raw GOWS node is absent' do
      payload = gows_payload('location_static', '_data' => { 'Info' => { 'Chat' => '5511888888888@c.us' } })

      expect(converter_for(payload)).to be_a(Waha::MessageConverters::Location)
    end

    it 'reads vCards from WAHA\'s engine-agnostic top-level field when the raw GOWS node is absent' do
      payload = gows_payload('contacts_array', '_data' => { 'Info' => { 'Chat' => '5511888888888@c.us' } })

      expect(converter_for(payload)).to be_a(Waha::MessageConverters::VCard)
    end

    it 'falls back for a location declared with no coordinates' do
      expect(converter_for(gows_payload('location_without_coordinates'))).to be_a(Waha::MessageConverters::Fallback)
    end

    it 'falls back for a shared contact declared with an empty vCard' do
      expect(converter_for(gows_payload('contact_without_vcard'))).to be_a(Waha::MessageConverters::Fallback)
    end

    it 'falls back for a list with no usable rows' do
      payload = { 'id' => 'x', '_data' => { 'Message' => { 'listMessage' => { 'title' => 'Empty', 'sections' => [] } } } }

      expect(converter_for(payload)).to be_a(Waha::MessageConverters::Fallback)
    end

    it 'falls back for an event with no title' do
      payload = { 'id' => 'x', '_data' => { 'Message' => { 'eventMessage' => { 'startTime' => 1_762_362_000 } } } }

      expect(converter_for(payload)).to be_a(Waha::MessageConverters::Fallback)
    end

    it 'falls back for an interactive message with no Pix payment button' do
      inner = { 'nativeFlowMessage' => { 'buttons' => [] } }
      payload = { 'id' => 'x', '_data' => { 'Message' => { 'interactiveMessage' => { 'interactiveMessage' => inner } } } }

      expect(converter_for(payload)).to be_a(Waha::MessageConverters::Fallback)
    end

    it 'falls back for a Pix button whose params carry no key' do
      payload = gows_payload('pix_payment')
      button = payload.dig('_data', 'Message', 'interactiveMessage', 'interactiveMessage', 'nativeFlowMessage', 'buttons').first
      button['buttonParamsJSON'] = '{"payment_settings":[{"type":"pix_static_code","pix_static_code":{"merchant_name":"Padaria Estrela"}}]}'

      expect(converter_for(payload)).to be_a(Waha::MessageConverters::Fallback)
    end

    it 'falls back for an album header declared with no expected media' do
      payload = { 'id' => 'x', '_data' => { 'Message' => { 'albumMessage' => { 'expectedImageCount' => 0, 'expectedVideoCount' => 0 } } } }

      expect(converter_for(payload)).to be_a(Waha::MessageConverters::Fallback)
    end

    it 'does not wrap a payload in FacebookAd when the ad reply carries no title or body' do
      payload = text_payload.merge(
        '_data' => { 'Message' => { 'extendedTextMessage' => { 'text' => 'Oi, tudo bem?', 'contextInfo' => { 'externalAdReply' => {} } } } }
      )

      expect(converter_for(payload)).to be_a(Waha::MessageConverters::Text)
    end

    it 'does not treat an ordinary reply as a status reply' do
      payload = text_payload.merge(
        'replyTo' => { 'id' => 'AAA111', 'body' => 'anterior' },
        '_data' => { 'Message' => { 'extendedTextMessage' => { 'contextInfo' => { 'remoteJID' => '5511888888888@s.whatsapp.net' } } } }
      )

      expect(converter_for(payload)).to be_a(Waha::MessageConverters::Text)
    end
  end

  describe 'the fallback converter' do
    it 'produces no content and marks an invalid structured payload as unsupported, never raw payload details' do
      converter = converter_for('id' => 'x', '_data' => { 'Message' => { 'pollCreationMessage' => { 'name' => 'Missing options' } } })

      expect(converter.content).to be_nil
      expect(converter.metadata).to eq(is_unsupported: true)
    end
  end

  describe 'the text and media converters' do
    it 'add no metadata of their own' do
      expect(converter_for(text_payload).metadata).to eq({})
      expect(converter_for(media_payload(kind: 'image')).metadata).to eq({})
    end
  end

  describe 'the status reply converter' do
    it 'keeps the reply\'s own text and adds the explicit status marker' do
      converter = converter_for(gows_payload('status_reply_text'))

      expect(converter.content).to eq('que promoção boa!')
      expect(converter.metadata).to eq(is_status_reply: true)
    end

    it 'still marks an unconvertible status reply as a visible fallback' do
      # Same capture with the reply's own text stripped: the wrapper must not
      # turn an empty payload into an empty bubble.
      payload = gows_payload('status_reply_text', 'body' => nil)
      payload.dig('_data', 'Message', 'extendedTextMessage').delete('text')

      converter = converter_for(payload)

      expect(converter.content).to be_nil
      expect(converter.metadata).to eq(is_unsupported: true, is_status_reply: true)
    end
  end
end
