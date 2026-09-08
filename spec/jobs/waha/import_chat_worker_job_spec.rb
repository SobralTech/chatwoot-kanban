require 'rails_helper'

describe Waha::ImportChatWorkerJob do
  let(:channel) { create(:channel_waha) }
  let(:window) { { 'window_start' => 1.month.ago.utc.iso8601, 'window_end' => Time.current.utc.iso8601 } }
  let(:importer) { instance_double(Waha::ChatHistoryImporter, run: 1) }
  let(:execution_id) { SecureRandom.uuid }

  before do
    channel.update_import_state!('status' => 'running', 'kind' => 'initial', 'execution_id' => execution_id)
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

      expect { described_class.perform_now(channel.id, window, 'initial', execution_id) }
        .to have_enqueued_job(described_class).with(channel.id, window, 'initial', execution_id).exactly(:once)

      expect(channel.import_chats.done.count).to eq(1)
      expect(channel.import_chats.pending.count).to eq(2)
    end
  end

  describe 'draining the queue' do
    it 'finalizes the import and enqueues no successor once no chat is left to claim' do
      expect { described_class.perform_now(channel.id, window, 'initial', execution_id) }
        .not_to have_enqueued_job(described_class)

      expect(channel.reload.import_state['status']).to eq('completed')
    end

    it 'leaves finalization to the worker still importing a chat' do
      queue_chats('a@c.us')
      channel.import_chats.first.update!(status: :importing)

      described_class.perform_now(channel.id, window, 'initial', execution_id)

      expect(channel.reload.import_state['status']).to eq('running')
    end

    it 'marks the import as failed when a chat failed' do
      queue_chats('a@c.us')
      channel.import_chats.first.update!(status: :failed, error: 'WAHA request failed')

      described_class.perform_now(channel.id, window, 'initial', execution_id)

      expect(channel.reload.import_state).to include('status' => 'failed', 'error' => 'WAHA request failed')
    end
  end

  describe 'a delayed worker from an earlier execution' do
    it 'does not claim or finalize rows from the current execution' do
      queue_chats('a@c.us')

      described_class.perform_now(channel.id, window, 'initial', SecureRandom.uuid)

      expect(importer).not_to have_received(:run)
      expect(channel.import_chats.pending.count).to eq(1)
      expect(channel.reload.import_state).to include('status' => 'running', 'execution_id' => execution_id)
    end
  end

  describe 'a chat that fails' do
    it 'marks the row failed and still hands off, so one bad chat cannot stall the pool' do
      queue_chats('a@c.us', 'b@c.us')
      allow(importer).to receive(:run).and_raise(StandardError, 'boom')

      expect { described_class.perform_now(channel.id, window, 'initial', execution_id) }
        .to have_enqueued_job(described_class).exactly(:once)

      expect(channel.import_chats.failed.count).to eq(1)
    end
  end

  # Reproduces the historical-flow half of ticket 03: a core contact-resolution
  # failure used to be absorbed inside Waha::ContactResolver, so ChatHistoryImporter
  # returned normally with 0 imported and this job called row.done! on a chat it
  # never actually processed. It must now surface as `failed`, never `done`.
  describe 'a chat whose contact resolution fails with a core error' do
    it 'marks the row failed, not done, and leaves the checkpoint unset' do
      allow(Waha::ChatHistoryImporter).to receive(:new).and_call_original
      chat_id = 'unresolvable@c.us'
      queue_chats(chat_id)

      stub_request(:get, %r{https://waha\.test/api/#{channel.session_name}/chats/#{chat_id}/messages\?})
        .to_return(status: 200, body: [{
          'id' => 'false_unresolvable@c.us_1', 'body' => 'hi', 'from' => chat_id, 'to' => '5511999999999@c.us',
          'fromMe' => false, 'timestamp' => 10.minutes.ago.to_i, 'type' => 'chat', 'hasMedia' => false,
          '_data' => { 'Info' => { 'Chat' => chat_id } }
        }].to_json, headers: { 'Content-Type' => 'application/json' })
      allow(Waha::ContactResolver).to receive(:from_payload).and_raise(CustomExceptions::Waha::TransientError, 'boom')

      described_class.perform_now(channel.id, window, 'initial', execution_id)

      row = channel.import_chats.find_by!(chat_id: chat_id)
      expect(row.status).to eq('failed')
      expect(row.cursor).to be_nil
      expect(row.imported_count).to eq(0)
      expect(waha_messages('false_unresolvable@c.us_1', Message.all).first).to be_nil
    end
  end
end
