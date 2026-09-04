require 'rails_helper'

RSpec.describe Channel::Waha, type: :model do
  self.use_transactional_tests = false

  let(:channel) { create(:channel_waha) }
  let(:window) do
    {
      'window_start' => 1.hour.ago.utc.iso8601,
      'window_end' => Time.current.utc.iso8601
    }
  end

  around do |example|
    clear_history_jobs
    example.run
  ensure
    clear_history_jobs
    clean_channel_data!
  end

  describe 'history import single-flight' do
    it 'lets only one concurrent trigger schedule and dispatch an execution' do
      results, errors = run_concurrently(2) do
        described_class.find(channel.id).enqueue_history_import!(window, kind: 'gap_fill')
      end

      aggregate_failures do
        expect(errors).to be_empty
        expect(results.count(true)).to eq(1)
        expect(history_import_jobs.count).to eq(1)

        execution_id = channel.reload.import_state.fetch('execution_id')
        expect(channel.import_state).to include('status' => 'scheduled', 'kind' => 'gap_fill')
        expect(channel.import_state['queued_window']).to be_nil

        clear_history_jobs
        fetcher, calls = counting_fetcher(['5511888888888@c.us'])
        allow(Waha::ChatOverviewFetcher).to receive(:new).and_return(fetcher)

        _, errors = run_concurrently(2) do
          Waha::HistoryImportJob.new.perform(channel.id, window, 'gap_fill', execution_id)
        end

        expect(errors).to be_empty
        expect(calls.call).to eq(1)
        expect(channel.reload.import_state['status']).to eq('running')
        expect(channel.import_chats.pluck(:chat_id)).to eq(['5511888888888@c.us'])
      end
    end

    it 'does not queue a second initial import while the first is scheduled' do
      channel.enqueue_history_import!(window, kind: 'initial')
      execution_id = channel.reload.import_state.fetch('execution_id')

      expect(channel.enqueue_history_import!(window, kind: 'initial')).to be(false)

      expect(history_import_jobs.count).to eq(1)
      expect(channel.reload.import_state).to include('status' => 'scheduled', 'execution_id' => execution_id)
      expect(channel.import_state['queued_window']).to be_nil
    end

    it 'keeps active chat checkpoints intact for initial, gap-fill, and periodic triggers' do
      channel.enqueue_history_import!(window, kind: 'initial')
      execution_id = channel.reload.import_state.fetch('execution_id')
      channel.start_scheduled_import!(execution_id)
      import_chat = WahaImportChat.create!(
        channel: channel, chat_id: '5511888888888@c.us', status: :importing, cursor: 123, imported_count: 4
      )
      clear_history_jobs

      gap_window = {
        'window_start' => 30.minutes.ago.utc.iso8601,
        'window_end' => Time.current.utc.iso8601
      }
      expect(channel.enqueue_history_import!(gap_window, kind: 'gap_fill')).to be(false)

      channel.update!(session_status: 'WORKING')
      Waha::PeriodicGapFillJob.perform_now

      state = channel.reload.import_state
      expect(history_import_jobs).to be_empty
      expect(state).to include('status' => 'running', 'execution_id' => execution_id, 'queued_kind' => 'gap_fill')
      expect(state['queued_window']).to be_present
      expect(import_chat.reload).to have_attributes(status: 'importing', cursor: 123, imported_count: 4)
    end

    it 'resumes a failed import with a new scheduled claim and existing checkpoints' do
      failed_execution_id = SecureRandom.uuid
      channel.update_import_state!(
        'status' => 'failed', 'execution_id' => failed_execution_id, 'kind' => 'gap_fill',
        'window_start' => window['window_start'], 'window_end' => window['window_end'], 'retries' => 3
      )
      completed_chat = WahaImportChat.create!(
        channel: channel, chat_id: 'done@c.us', status: :done, cursor: 100, imported_count: 8
      )
      retried_chat = WahaImportChat.create!(
        channel: channel, chat_id: 'retry@c.us', status: :failed, cursor: 50, imported_count: 2
      )

      expect(channel.retry_failed_import!).to be(true)

      state = channel.reload.import_state
      expect(history_import_jobs.count).to eq(1)
      expect(state).to include('status' => 'scheduled', 'kind' => 'gap_fill', 'retries' => 0)
      expect(state['execution_id']).not_to eq(failed_execution_id)
      expect(completed_chat.reload).to have_attributes(status: 'done', cursor: 100, imported_count: 8)
      expect(retried_chat.reload).to have_attributes(status: 'pending', cursor: 50, imported_count: 2)
    end
  end

  describe 'connection identity' do
    it 'normalizes the WAHA URL and session name before persistence' do
      configured_channel = build(
        :channel_waha,
        account: channel.account,
        waha_url: ' HTTPS://WAHA.TEST:443/ ',
        session_name: ' support team '
      )

      expect(configured_channel).to be_valid
      expect(configured_channel).to have_attributes(
        waha_url: 'https://waha.test',
        session_name: 'support_team',
        normalized_waha_url: 'https://waha.test',
        normalized_session_name: 'support_team'
      )
    end

    it 'rejects an equivalent connection already used by another inbox' do
      channel.update!(waha_url: 'https://waha.test', session_name: 'shared_session')
      duplicate_channel = build(
        :channel_waha,
        account: channel.account,
        waha_url: 'HTTPS://WAHA.TEST:443/',
        session_name: ' shared session '
      )

      expect(duplicate_channel).not_to be_valid
      expect(duplicate_channel.errors[:base]).to include(I18n.t('errors.messages.waha_connection_in_use'))
    end

    it 'does not allow a new connection to reuse an identity reported as a legacy conflict' do
      channel.update!(waha_url: 'https://waha.test', session_name: 'legacy_session')
      # Simulates the non-destructive flag written by the migration for legacy duplicates.
      # rubocop:disable Rails/SkipsModelValidations
      channel.update_column(:connection_identity_conflict, true)
      # rubocop:enable Rails/SkipsModelValidations
      duplicate_channel = build(
        :channel_waha,
        account: channel.account,
        waha_url: 'https://waha.test/',
        session_name: 'legacy_session'
      )

      expect(duplicate_channel).not_to be_valid
      expect(duplicate_channel.errors[:base]).to include(I18n.t('errors.messages.waha_connection_in_use'))
    end

    it 'enforces the normalized connection identity in the database under concurrent inserts' do
      attributes = {
        account_id: channel.account_id,
        waha_url: 'https://waha.test',
        normalized_waha_url: 'https://waha.test',
        api_key: 'test-api-key',
        session_name: 'concurrent_session',
        normalized_session_name: 'concurrent_session',
        connection_identity_conflict: false,
        created_at: Time.current,
        updated_at: Time.current
      }

      results, errors = run_concurrently(2) do
        # This deliberately bypasses validations to prove the database constraint, not the model validation.
        # rubocop:disable Rails/SkipsModelValidations
        described_class.transaction do
          described_class.insert_all!([attributes.merge(webhook_token: SecureRandom.uuid)])
        end
        # rubocop:enable Rails/SkipsModelValidations
      end

      expect(results.size).to eq(1)
      expect(errors.map(&:class).map(&:name)).to include('ActiveRecord::RecordNotUnique')
      expect(described_class.where(normalized_waha_url: 'https://waha.test', normalized_session_name: 'concurrent_session').count).to eq(1)
    end
  end

  private

  def history_import_jobs
    ActiveJob::Base.queue_adapter.enqueued_jobs.select { |job| job[:job] == Waha::HistoryImportJob }
  end

  def clear_history_jobs
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  end

  def counting_fetcher(chat_ids)
    mutex = Mutex.new
    calls = 0
    fetcher = Object.new
    fetcher.define_singleton_method(:all) do
      mutex.synchronize { calls += 1 }
      chat_ids
    end
    [fetcher, -> { mutex.synchronize { calls } }]
  end

  def run_concurrently(count)
    barrier = Concurrent::CyclicBarrier.new(count)
    results = Concurrent::Array.new
    errors = Queue.new
    threads = Array.new(count) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          barrier.wait
          results << yield
        end
      rescue StandardError => e
        errors << e
      end
    end

    Timeout.timeout(10.seconds) { threads.each(&:join) }
    [results, errors_from(errors)]
  ensure
    threads&.each(&:kill)
    ActiveRecord::Base.connection_handler.clear_active_connections!
  end

  def errors_from(queue)
    errors = []
    errors << queue.pop until queue.empty?
    errors
  end

  def clean_channel_data!
    channel_ids = Channel::Waha.where(account_id: channel.account_id).pluck(:id)
    account_id = channel.account_id
    inbox_ids = Inbox.where(channel_type: described_class.name, channel_id: channel_ids).pluck(:id)

    WahaImportChat.where(channel_waha_id: channel_ids).delete_all
    Inbox.where(id: inbox_ids).delete_all
    described_class.where(id: channel_ids).delete_all
    Account.where(id: account_id).delete_all
  end
end
