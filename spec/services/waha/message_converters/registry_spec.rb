require 'rails_helper'

# Contract tests for the converter registry: given a WAHA payload, it must
# select a converter that keeps the already-supported types working exactly
# as before, and must never let an unrecognized or malformed payload resolve
# to "nothing" (no content, no attachment, no visible marker).
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

  describe '.for' do
    Waha::MediaAttacher::MEDIA_KINDS.each do |kind|
      it "selects the media converter for a #{kind} payload" do
        converter = described_class.for(channel: channel, payload: media_payload(kind: kind))

        expect(converter).to be_a(Waha::MessageConverters::Media)
      end
    end

    it 'selects the text converter for a plain text payload' do
      converter = described_class.for(channel: channel, payload: text_payload)

      expect(converter).to be_a(Waha::MessageConverters::Text)
    end

    it 'selects the fallback converter for an unsupported GOWS message type' do
      converter = described_class.for(channel: channel, payload: poll_payload)

      expect(converter).to be_a(Waha::MessageConverters::Fallback)
    end

    it 'selects the fallback converter for a declared media type with no media info and no caption' do
      converter = described_class.for(channel: channel, payload: { 'id' => 'x', 'type' => 'image', 'hasMedia' => false })

      expect(converter).to be_a(Waha::MessageConverters::Fallback)
    end

    it 'prefers text over the fallback when an unrecognized payload still carries a body' do
      converter = described_class.for(channel: channel, payload: { 'id' => 'x', 'hasMedia' => false, 'body' => 'texto qualquer' })

      expect(converter).to be_a(Waha::MessageConverters::Text)
    end
  end

  describe 'the fallback converter' do
    it 'produces no content and marks the message as unsupported, never raw payload details' do
      converter = described_class.for(channel: channel, payload: poll_payload)

      expect(converter.content).to be_nil
      expect(converter.metadata).to eq(is_unsupported: true)
    end
  end

  describe 'the text and media converters' do
    it 'add no metadata of their own' do
      expect(described_class.for(channel: channel, payload: text_payload).metadata).to eq({})
      expect(described_class.for(channel: channel, payload: media_payload(kind: 'image')).metadata).to eq({})
    end
  end
end
