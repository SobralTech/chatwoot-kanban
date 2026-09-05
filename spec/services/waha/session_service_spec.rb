require 'rails_helper'

describe Waha::SessionService do
  it 'subscribes every WAHA session to the separate GOWS poll vote event' do
    expect(described_class::WEBHOOK_EVENTS).to include('poll.vote')
  end
end
