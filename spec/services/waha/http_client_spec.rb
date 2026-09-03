require 'rails_helper'

describe Waha::HttpClient do
  let(:channel) { build_stubbed(:channel_waha) }

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
