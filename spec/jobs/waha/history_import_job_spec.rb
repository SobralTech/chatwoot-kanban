require 'rails_helper'

describe Waha::HistoryImportJob do
  let(:channel) { create(:channel_waha) }
  let(:window) { { 'window_start' => 6.months.ago.utc.iso8601, 'window_end' => Time.current.utc.iso8601 } }
  let(:fetcher) { instance_double(Waha::ChatOverviewFetcher, all: []) }

  before do
    allow(Waha::ChatOverviewFetcher).to receive(:new).and_return(fetcher)
  end

  def schedule_import(kind)
    channel.enqueue_history_import!(window, kind: kind)
    channel.reload.import_state.fetch('execution_id')
  end

  it 'retries an initial import when GOWS has not populated the chat overview yet' do
    execution_id = schedule_import('initial')
    clear_enqueued_jobs

    expect { described_class.perform_now(channel.id, window, 'initial', execution_id) }
      .to have_enqueued_job(described_class).with(channel.id, window, 'initial', anything).exactly(:once)

    expect(channel.reload.import_state).to include('status' => 'scheduled', 'retries' => 1)
    expect(channel.import_state['execution_id']).not_to eq(execution_id)
    expect(channel.import_chats).to be_empty
  end

  it 'passes the gap-fill kind to each chat worker' do
    allow(fetcher).to receive(:all).and_return(['5511888888888@c.us'])
    execution_id = schedule_import('gap_fill')
    clear_enqueued_jobs

    expect { described_class.perform_now(channel.id, window, 'gap_fill', execution_id) }
      .to have_enqueued_job(Waha::ImportChatWorkerJob).with(channel.id, window, 'gap_fill', execution_id).exactly(:once)
  end

  describe 'bounded chat worker dispatch' do
    it 'enqueues no more than WAHA_IMPORT_CONCURRENCY when more chats are pending' do
      stub_const('Waha::HistoryImportJob::WORKER_POOL', 2)
      allow(fetcher).to receive(:all).and_return(%w[a@c.us b@c.us c@c.us d@c.us])
      execution_id = schedule_import('initial')
      clear_enqueued_jobs

      expect { described_class.perform_now(channel.id, window, 'initial', execution_id) }
        .to have_enqueued_job(Waha::ImportChatWorkerJob).exactly(2)

      expect(channel.import_chats.pending.count).to eq(4)
    end

    it 'enqueues only the pending chats when fewer remain than the worker ceiling' do
      stub_const('Waha::HistoryImportJob::WORKER_POOL', 4)
      allow(fetcher).to receive(:all).and_return(%w[a@c.us b@c.us])
      execution_id = schedule_import('gap_fill')
      clear_enqueued_jobs

      expect { described_class.perform_now(channel.id, window, 'gap_fill', execution_id) }
        .to have_enqueued_job(Waha::ImportChatWorkerJob).exactly(2)

      expect(channel.import_chats.pending.count).to eq(2)
    end
  end
end
