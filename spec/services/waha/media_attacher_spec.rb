require 'rails_helper'

describe Waha::MediaAttacher do
  let(:channel) { build_stubbed(:channel_waha) }
  let(:media_url) { 'https://waha.test/api/files/abc.jpeg' }

  def media_payload(id: 'false_5511888888888@c.us_MEDIA01', mimetype: 'image/jpeg')
    {
      'id' => id,
      'hasMedia' => true,
      'type' => 'image',
      'media' => { 'url' => 'http://localhost:3000/api/files/abc.jpeg', 'mimetype' => mimetype }
    }
  end

  describe '#download' do
    it 'returns the file on a 2xx response' do
      stub_request(:get, media_url).to_return(status: 200, body: 'bytes', headers: { 'Content-Type' => 'image/jpeg' })

      file = described_class.new(channel: channel, payload: media_payload).download

      expect(file.read).to eq('bytes')
    end

    it 'raises a MediaDownloadError on a 5xx response (worth retrying)' do
      stub_request(:get, media_url).to_return(status: 503)

      expect { described_class.new(channel: channel, payload: media_payload).download }
        .to raise_error(CustomExceptions::Waha::MediaDownloadError)
    end

    it 'raises a MediaDownloadError on a timeout (worth retrying)' do
      stub_request(:get, media_url).to_timeout

      expect { described_class.new(channel: channel, payload: media_payload).download }
        .to raise_error(CustomExceptions::Waha::MediaDownloadError)
    end

    it 'raises a MediaDownloadError on a connection failure (worth retrying)' do
      stub_request(:get, media_url).to_raise(Errno::ECONNREFUSED)

      expect { described_class.new(channel: channel, payload: media_payload).download }
        .to raise_error(CustomExceptions::Waha::MediaDownloadError)
    end

    it 'returns nil without raising on a 404 (expired media, not worth retrying)' do
      stub_request(:get, media_url).to_return(status: 404)

      expect(described_class.new(channel: channel, payload: media_payload).download).to be_nil
    end

    it 'skips the network call entirely when terminal is set' do
      described_class.new(channel: channel, payload: media_payload, terminal: true).download

      expect(a_request(:get, media_url)).not_to have_been_made
    end

    it 'returns nil for a payload with no media, without making a request' do
      described_class.new(channel: channel, payload: { 'id' => 'x', 'hasMedia' => false }).download

      expect(a_request(:get, media_url)).not_to have_been_made
    end
  end

  describe '#attach_to' do
    it 'attaches the downloaded file and clears no fallback marker' do
      stub_request(:get, media_url).to_return(status: 200, body: 'bytes', headers: { 'Content-Type' => 'image/jpeg' })
      message = build(:message, content: nil)

      described_class.new(channel: channel, payload: media_payload).attach_to(message)

      expect(message.attachments.size).to eq(1)
      expect(message.content_attributes['media_download_failed']).to be_nil
    end

    it 'clears pending and unsupported state while preserving a real caption' do
      stub_request(:get, media_url).to_return(status: 200, body: 'bytes', headers: { 'Content-Type' => 'image/jpeg' })
      message = build(
        :message,
        content: 'real caption',
        content_attributes: {
          'media_download_pending' => true,
          'media_download_provenance' => 'waha_history', 'is_unsupported' => true
        }
      )

      described_class.new(channel: channel, payload: media_payload).attach_to(message)

      expect(message.attachments.size).to eq(1)
      expect(message.content).to eq('real caption')
      expect(message.content_attributes).not_to have_key('media_download_pending')
      expect(message.content_attributes).not_to have_key('is_unsupported')
    end

    it 'does not erase a live caption that happens to equal the pending translation' do
      stub_request(:get, media_url).to_return(status: 200, body: 'bytes', headers: { 'Content-Type' => 'image/jpeg' })
      message = build(:message, content: I18n.t('conversations.messages.waha_media_pending'))

      described_class.new(channel: channel, payload: media_payload).attach_to(message)

      expect(message.attachments.size).to eq(1)
      expect(message.content).to eq(I18n.t('conversations.messages.waha_media_pending'))
    end

    it 'marks a visible fallback (content + content_attributes) on a terminal download failure' do
      stub_request(:get, media_url).to_return(status: 404)
      message = build(:message, content: nil)

      described_class.new(channel: channel, payload: media_payload).attach_to(message)

      expect(message.attachments).to be_empty
      expect(message.content_attributes['media_download_failed']).to be(true)
      expect(message.content).to eq(I18n.t('conversations.messages.waha_media_unavailable'))
    end

    it 'marks the same visible fallback when the caller already exhausted retries (terminal: true)' do
      message = build(:message, content: nil)

      described_class.new(channel: channel, payload: media_payload, terminal: true).attach_to(message)

      expect(a_request(:get, media_url)).not_to have_been_made
      expect(message.attachments).to be_empty
      expect(message.content_attributes['media_download_failed']).to be(true)
    end

    it 'replaces only the pending placeholder on terminal failure' do
      stub_request(:get, media_url).to_return(status: 404)
      message = build(
        :message,
        content: I18n.t('conversations.messages.waha_media_pending'),
        content_attributes: {
          'media_download_pending' => true, 'media_download_provenance' => 'waha_history',
          'media_download_content' => 'waha_media_pending', 'is_unsupported' => true
        }
      )

      described_class.new(channel: channel, payload: media_payload).attach_to(message)

      expect(message.attachments).to be_empty
      expect(message.content).to eq(I18n.t('conversations.messages.waha_media_unavailable'))
      expect(message.content_attributes['media_download_failed']).to be(true)
      expect(message.content_attributes).not_to have_key('media_download_pending')
      expect(message.content_attributes).not_to have_key('is_unsupported')
    end

    it 'does not convert a live caption matching the pending translation on terminal failure' do
      stub_request(:get, media_url).to_return(status: 404)
      message = build(:message, content: I18n.t('conversations.messages.waha_media_pending'))

      described_class.new(channel: channel, payload: media_payload).attach_to(message)

      expect(message.content).to eq(I18n.t('conversations.messages.waha_media_pending'))
      expect(message.content_attributes['media_download_failed']).to be(true)
    end

    it 'preserves an existing caption instead of overwriting it with the fallback label' do
      stub_request(:get, media_url).to_return(status: 404)
      message = build(
        :message,
        content: 'check this out',
        content_attributes: {
          'media_download_pending' => true,
          'media_download_provenance' => 'waha_history', 'is_unsupported' => true
        }
      )

      described_class.new(channel: channel, payload: media_payload).attach_to(message)

      expect(message.content).to eq('check this out')
      expect(message.content_attributes['media_download_failed']).to be(true)
      expect(message.content_attributes).not_to have_key('media_download_pending')
      expect(message.content_attributes).not_to have_key('is_unsupported')
    end

    it 'does not attach anything or mark a failure for a message with no media' do
      message = build(:message, content: 'just text')

      described_class.new(channel: channel, payload: { 'id' => 'x', 'hasMedia' => false }).attach_to(message)

      expect(message.attachments).to be_empty
      expect(message.content_attributes['media_download_failed']).to be_nil
      expect(message.content).to eq('just text')
    end
  end
end
