require 'rails_helper'

describe Waha::ImportChatWorkerJob do
  let(:channel) { create(:channel_waha) }
  let(:window) { { 'window_start' => 1.month.ago.utc.iso8601, 'window_end' => Time.current.utc.iso8601 } }
  let(:importer) { instance_double(Waha::ChatHistoryImporter, run: 1) }

  before do
    channel.update_import_state!('status' => 'running', 'kind' => 'initial')
    allow(Waha::ChatHistoryImporter).to receive(:new).and_return(importer)
  end

  def queue_chats(*chat_ids)
    chat_ids.each { |chat_id| WahaImportChat.create!(channel: channel, chat_id: chat_id) }
  end

  # The worker used to drain the whole queue inside one execution, holding a Sidekiq
  # thread (and its database connection) for the entire import. With several channels
  # importing at once — every channel reconnects together after a WAHA restart — that
  # occupied every thread in the process and starved all other queues, including the
  # one carrying live inbound messages.
  describe 'thread occupancy' do
    it 'imports one chat per execution and hands the rest to a successor job' do
      queue_chats('a@c.us', 'b@c.us', 'c@c.us')

      expect { described_class.perform_now(channel.id, window) }
        .to have_enqueued_job(described_class).with(channel.id, window).exactly(:once)

      expect(channel.import_chats.done.count).to eq(1)
      expect(channel.import_chats.pending.count).to eq(2)
    end
  end

  describe 'draining the queue' do
    it 'finalizes the import and enqueues no successor once no chat is left to claim' do
      expect { described_class.perform_now(channel.id, window) }
        .not_to have_enqueued_job(described_class)

      expect(channel.reload.import_state['status']).to eq('done')
    end

    it 'leaves finalization to the worker still importing a chat' do
      queue_chats('a@c.us')
      channel.import_chats.first.update!(status: :importing)

      described_class.perform_now(channel.id, window)

      expect(channel.reload.import_state['status']).to eq('running')
    end
  end

  describe 'a chat that fails' do
    it 'marks the row failed and still hands off, so one bad chat cannot stall the pool' do
      queue_chats('a@c.us', 'b@c.us')
      allow(importer).to receive(:run).and_raise(StandardError, 'boom')

      expect { described_class.perform_now(channel.id, window) }
        .to have_enqueued_job(described_class).exactly(:once)

      expect(channel.import_chats.failed.count).to eq(1)
    end
  end
end
