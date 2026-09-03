require 'rails_helper'

describe Waha::HistoryImportJob do
  let(:channel) { create(:channel_waha) }
  let(:window) { { 'window_start' => 6.months.ago.utc.iso8601, 'window_end' => Time.current.utc.iso8601 } }
  let(:fetcher) { instance_double(Waha::ChatOverviewFetcher, all: []) }

  before do
    allow(Waha::ChatOverviewFetcher).to receive(:new).and_return(fetcher)
  end

  it 'retries an initial import when GOWS has not populated the chat overview yet' do
    expect { described_class.perform_now(channel.id, window, 'initial') }
      .to have_enqueued_job(described_class).with(channel.id, window, 'initial').exactly(:once)

    expect(channel.reload.import_state).to include('status' => 'running', 'retries' => 1)
    expect(channel.import_chats).to be_empty
  end
end
