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

  # A real GOWS poll payload: no top-level `type`, no `body`, no `hasMedia` — the
  # structured content lives entirely under `_data.Message.pollCreationMessage`.
  # Poll conversion is out of scope for this ticket (see ticket 20); the registry
  # must still resolve this to the visible fallback instead of a blank message.
  def poll_payload
    {
      'id' => 'x',
      'hasMedia' => false,
      '_data' => {
        'Message' => {
          'pollCreationMessage' => {
            'name' => 'Qual dia é melhor?',
            'options' => [{ 'optionName' => 'Segunda' }, { 'optionName' => 'Terça' }]
          }
        }
      }
    }
  end

  def converter_for(payload)
    described_class.for(channel: channel, payload: payload)
  end

  describe '.for' do
    Waha::MediaAttacher::MEDIA_KINDS.each do |kind|
      it "selects the media converter for a #{kind} payload" do
        expect(converter_for(media_payload(kind: kind))).to be_a(Waha::MessageConverters::Media)
      end
    end

    it 'selects the text converter for a plain text payload' do
      expect(converter_for(text_payload)).to be_a(Waha::MessageConverters::Text)
    end

    it 'selects the fallback converter for an unsupported GOWS message type' do
      expect(converter_for(poll_payload)).to be_a(Waha::MessageConverters::Fallback)
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

    it 'does not treat an ordinary reply as a status reply' do
      payload = text_payload.merge(
        'replyTo' => { 'id' => 'AAA111', 'body' => 'anterior' },
        '_data' => { 'Message' => { 'extendedTextMessage' => { 'contextInfo' => { 'remoteJID' => '5511888888888@s.whatsapp.net' } } } }
      )

      expect(converter_for(payload)).to be_a(Waha::MessageConverters::Text)
    end
  end

  describe 'the fallback converter' do
    it 'produces no content and marks the message as unsupported, never raw payload details' do
      converter = converter_for(poll_payload)

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
