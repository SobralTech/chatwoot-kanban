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

  it 'treats an empty overview as one stable pass and schedules another full discovery' do
    execution_id = schedule_import('initial')
    pass_id = channel.reload.import_state.fetch('pass_id')
    clear_enqueued_jobs

    expect { described_class.perform_now(channel.id, window, 'initial', execution_id) }
      .to have_enqueued_job(described_class).with(channel.id, window, 'initial', execution_id, anything).exactly(:once)

    expect(channel.reload.import_state).to include(
      'status' => 'running', 'phase' => 'settling', 'execution_id' => execution_id,
      'pass_number' => 2, 'stable_passes' => 1
    )
    expect(channel.import_state['pass_id']).not_to eq(pass_id)
    expect(channel.import_chats).to be_empty
  end

  it 'passes the gap-fill kind to each chat worker' do
    allow(fetcher).to receive(:all).and_return(['5511888888888@c.us'])
    execution_id = schedule_import('gap_fill')
    pass_id = channel.reload.import_state.fetch('pass_id')
    clear_enqueued_jobs

    expect { described_class.perform_now(channel.id, window, 'gap_fill', execution_id) }
      .to have_enqueued_job(Waha::ImportChatWorkerJob).with(channel.id, window, 'gap_fill', execution_id, pass_id).exactly(:once)
  end

  it 'retries a transient discovery failure with the same execution and pass tokens' do
    allow(fetcher).to receive(:all).and_raise(CustomExceptions::Waha::TransientError, 'unavailable')
    execution_id = schedule_import('initial')
    pass_id = channel.reload.import_state.fetch('pass_id')
    clear_enqueued_jobs

    expect { described_class.perform_now(channel.id, window, 'initial', execution_id, pass_id) }
      .to have_enqueued_job(described_class).with(channel.id, window, 'initial', execution_id, pass_id).exactly(:once)

    expect(channel.reload.import_state).to include(
      'status' => 'running', 'phase' => 'settling', 'execution_id' => execution_id,
      'pass_id' => pass_id, 'retries' => 1
    )
  end

  it 'makes an invalid discovery contract terminal instead of retrying it' do
    allow(fetcher).to receive(:all).and_raise(CustomExceptions::Waha::ApiError, 'invalid payload')
    execution_id = schedule_import('initial')
    pass_id = channel.reload.import_state.fetch('pass_id')
    clear_enqueued_jobs

    expect { described_class.perform_now(channel.id, window, 'initial', execution_id, pass_id) }
      .not_to have_enqueued_job(described_class)

    expect(channel.reload.import_state).to include(
      'status' => 'failed', 'failure_reason' => 'dispatcher_terminal', 'error' => 'invalid payload'
    )
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

  describe 'convergent initial passes' do
    it 'retains chat growth when a crashed dispatcher retries after seeding rows' do
      allow(fetcher).to receive(:all).and_return(['seeded-before-crash@c.us'])
      execution_id = schedule_import('initial')
      state = channel.reload.import_state
      channel.import_chats.create!(
        chat_id: 'seeded-before-crash@c.us', execution_id: execution_id,
        pass_id: state.fetch('pass_id'), pass_number: 1, discovered_pass: 1
      )
      clear_enqueued_jobs

      described_class.perform_now(channel.id, window, 'initial', execution_id, state.fetch('pass_id'))

      expect(channel.reload.import_state).to include('phase' => 'importing', 'pass_new_chats' => 1)
    end

    it 'completes only after two consecutive stable passes and the quiet period' do
      stub_const('Waha::HistoryImportJob::PASS_INTERVAL', 0.seconds)
      stub_const('Waha::HistoryImportJob::QUIET_PERIOD', 0.seconds)
      execution_id = schedule_import('initial')
      clear_enqueued_jobs

      first_pass_id = channel.reload.import_state.fetch('pass_id')
      described_class.perform_now(channel.id, window, 'initial', execution_id, first_pass_id)

      expect(channel.reload.import_state).to include(
        'status' => 'running', 'phase' => 'settling', 'stable_passes' => 1, 'pass_number' => 2
      )

      second_pass_id = channel.import_state.fetch('pass_id')
      described_class.perform_now(channel.id, window, 'initial', execution_id, second_pass_id)

      expect(channel.reload.import_state).to include(
        'status' => 'completed', 'stable_passes' => 2, 'pass_number' => 2, 'media_pending' => true
      )
    end

    it 'keeps the union of chats discovered late and resets the cursor for a full later pass' do
      stub_const('Waha::HistoryImportJob::PASS_INTERVAL', 0.seconds)
      stub_const('Waha::HistoryImportJob::QUIET_PERIOD', 0.seconds)
      allow(fetcher).to receive(:all).and_return(['first@c.us'])
      execution_id = schedule_import('initial')
      clear_enqueued_jobs

      first_pass_id = channel.reload.import_state.fetch('pass_id')
      described_class.perform_now(channel.id, window, 'initial', execution_id, first_pass_id)
      first = channel.import_chats.find_by!(chat_id: 'first@c.us')
      first.update!(
        status: :done, cursor: 123, cursor_message_id: 'OLD', pass_observed_message_count: 1,
        pass_observed_message_digest: 'first-pass'
      )
      channel.finalize_import_if_drained!(execution_id, first_pass_id)

      second_pass_id = channel.reload.import_state.fetch('pass_id')
      expect(first.reload).to have_attributes(status: 'pending', cursor: nil, cursor_message_id: nil)

      allow(fetcher).to receive(:all).and_return(%w[first@c.us late@c.us])
      clear_enqueued_jobs
      described_class.perform_now(channel.id, window, 'initial', execution_id, second_pass_id)

      expect(channel.import_chats.order(:chat_id).pluck(:chat_id)).to eq(%w[first@c.us late@c.us])
      expect(channel.import_chats.find_by!(chat_id: 'late@c.us')).to have_attributes(
        execution_id: execution_id, pass_id: second_pass_id, discovered_pass: 2, status: 'pending'
      )
      expect(channel.reload.import_state).to include('pass_new_chats' => 1, 'pass_number' => 2)
    end

    it 'resets the stable-pass count when a later pass observes a new canonical message' do
      stub_const('Waha::HistoryImportJob::PASS_INTERVAL', 0.seconds)
      stub_const('Waha::HistoryImportJob::QUIET_PERIOD', 0.seconds)
      execution_id = schedule_import('initial')
      state = channel.reload.import_state
      pass_id = state.fetch('pass_id')
      channel.claim_import_pass!(execution_id, pass_id)
      channel.begin_import_pass!(execution_id, pass_id, channel.import_state.fetch('dispatcher_token'), new_chats: 0)
      channel.update_import_state!('stable_passes' => 1)
      channel.import_chats.create!(
        chat_id: 'growing@c.us', execution_id: execution_id, pass_id: pass_id,
        discovered_pass: 0, status: :done, observed_message_count: 1, observed_message_digest: 'old',
        pass_observed_message_count: 2, pass_observed_message_digest: 'new'
      )
      clear_enqueued_jobs

      channel.finalize_import_if_drained!(execution_id, pass_id)

      expect(channel.reload.import_state).to include(
        'status' => 'running', 'phase' => 'settling', 'stable_passes' => 0,
        'pass_new_messages' => 0, 'pass_number' => 2
      )
      expect(channel.import_chats.first.reload).to have_attributes(
        observed_message_count: 2, observed_message_digest: 'new', cursor: nil
      )
    end

    it 'fails observably when the quiet period cannot fit inside the settling limit' do
      stub_const('Waha::HistoryImportJob::PASS_INTERVAL', 0.seconds)
      stub_const('Waha::HistoryImportJob::QUIET_PERIOD', 10.minutes)
      stub_const('Waha::HistoryImportJob::MAX_SETTLING_TIME', 1.minute)
      execution_id = schedule_import('initial')
      clear_enqueued_jobs

      described_class.perform_now(channel.id, window, 'initial', execution_id, channel.reload.import_state.fetch('pass_id'))

      expect(channel.reload.import_state).to include(
        'status' => 'failed', 'failure_reason' => 'not_converged', 'not_converged_reason' => 'settling_timeout'
      )
    end

    it 'fails observably when the pass budget is exhausted before two stable passes' do
      stub_const('Waha::HistoryImportJob::MAX_PASSES', 1)
      stub_const('Waha::HistoryImportJob::QUIET_PERIOD', 0.seconds)
      execution_id = schedule_import('initial')
      clear_enqueued_jobs

      described_class.perform_now(channel.id, window, 'initial', execution_id, channel.reload.import_state.fetch('pass_id'))

      expect(channel.reload.import_state).to include(
        'status' => 'failed', 'failure_reason' => 'not_converged', 'not_converged_reason' => 'max_passes'
      )
    end
  end
end
