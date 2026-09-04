require 'rails_helper'

describe Waha::HttpClient do
  let(:channel) { build_stubbed(:channel_waha) }
  let(:client) { described_class.new(channel: channel) }

  describe '#post' do
    it 'returns the parsed body on a 2xx response' do
      stub_request(:post, 'https://waha.test/api/sendText')
        .to_return(status: 201, body: '{"id":"true_123"}', headers: { 'Content-Type' => 'application/json' })

      expect(client.post('sendText', { text: 'hi' })).to eq('id' => 'true_123')
    end

    it 'raises a non-transient ApiError on a 4xx response, not a TransientError' do
      stub_request(:post, 'https://waha.test/api/sendText')
        .to_return(status: 422, body: '{"message":"invalid chatId"}', headers: { 'Content-Type' => 'application/json' })

      expect { client.post('sendText', {}) }
        .to raise_error(an_instance_of(CustomExceptions::Waha::ApiError)
          .and(having_attributes(message: 'WAHA request failed (HTTP 422): invalid chatId')))
    end

    it 'raises a TransientError on a 5xx response' do
      stub_request(:post, 'https://waha.test/api/sendText')
        .to_return(status: 503, body: '{"message":"session not ready"}', headers: { 'Content-Type' => 'application/json' })

      expect { client.post('sendText', {}) }
        .to raise_error(CustomExceptions::Waha::TransientError, 'WAHA request failed (HTTP 503): session not ready')
    end

    it 'raises a TransientError on a timeout' do
      stub_request(:post, 'https://waha.test/api/sendText').to_timeout

      expect { client.post('sendText', {}) }.to raise_error(CustomExceptions::Waha::TransientError, /transport/)
    end

    it 'raises a TransientError on a transport failure' do
      stub_request(:post, 'https://waha.test/api/sendText').to_raise(Errno::ECONNREFUSED)

      expect { client.post('sendText', {}) }.to raise_error(CustomExceptions::Waha::TransientError, /transport/)
    end

    it 'raises a non-transient ApiError on an invalid (unparseable) response body' do
      stub_request(:post, 'https://waha.test/api/sendText')
        .to_return(status: 200, body: 'not json', headers: { 'Content-Type' => 'application/json' })

      expect { client.post('sendText', {}) }
        .to raise_error(an_instance_of(CustomExceptions::Waha::ApiError))
    end
  end

  describe '#get_array' do
    it 'returns an array response' do
      stub_request(:get, 'https://waha.test/api/test')
        .to_return(status: 200, body: '[{"id":"chat"}]', headers: { 'Content-Type' => 'application/json' })

      expect(described_class.new(channel: channel).get_array('test')).to eq([{ 'id' => 'chat' }])
    end

    it 'raises when WAHA returns an unsuccessful response' do
      stub_request(:get, 'https://waha.test/api/test')
        .to_return(status: 422, body: '{"message":"Session is not ready"}', headers: { 'Content-Type' => 'application/json' })

      expect { described_class.new(channel: channel).get_array('test') }
        .to raise_error(CustomExceptions::Waha::ApiError, 'WAHA request failed (HTTP 422): Session is not ready')
    end

    it 'raises when WAHA returns a non-array success response' do
      stub_request(:get, 'https://waha.test/api/test')
        .to_return(status: 200, body: '{"status":"ok"}', headers: { 'Content-Type' => 'application/json' })

      expect { described_class.new(channel: channel).get_array('test') }
        .to raise_error(CustomExceptions::Waha::ApiError, 'WAHA returned Hash instead of an array')
    end
  end
end
