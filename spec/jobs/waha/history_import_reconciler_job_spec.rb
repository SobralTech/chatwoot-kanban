require 'rails_helper'

describe Waha::HistoryImportReconcilerJob do
  let(:channel) { create(:channel_waha) }
  let(:window) { { 'window_start' => 1.month.ago.utc.iso8601, 'window_end' => Time.current.utc.iso8601 } }

  it 'reclaims an expired chat lease and later reenqueues the resumable pass' do
    channel.enqueue_history_import!(window, kind: 'gap_fill')
    state = channel.reload.import_state
    execution_id = state.fetch('execution_id')
    pass_id = state.fetch('pass_id')
    channel.claim_import_pass!(execution_id, pass_id)
    channel.import_chats.create!(
      chat_id: 'stuck@c.us', execution_id: execution_id, pass_id: pass_id,
      pass_number: 1, status: :importing, lease_token: 'dead-worker', lease_expires_at: 1.minute.ago,
      cursor: 123, cursor_message_id: 'CHECKPOINT'
    )
    channel.update_import_state!('phase' => 'importing')
    clear_enqueued_jobs

    described_class.perform_now

    row = channel.import_chats.first
    expect(row.reload).to have_attributes(
      status: 'pending', attempts: 1, cursor: 123, cursor_message_id: 'CHECKPOINT', lease_token: nil
    )
    expect { row.heartbeat!('dead-worker', lease_duration: 5.minutes) }
      .to raise_error(CustomExceptions::Waha::StaleImportWorker)

    travel 11.seconds do
      expect { described_class.perform_now }
        .to have_enqueued_job(Waha::ImportChatWorkerJob)
        .with(channel.id, window, 'gap_fill', execution_id, pass_id)
    end
  end

  it 'reclaims a pre-deploy importing row that has no lease metadata' do
    channel.enqueue_history_import!(window, kind: 'gap_fill')
    state = channel.reload.import_state
    execution_id = state.fetch('execution_id')
    pass_id = state.fetch('pass_id')
    channel.claim_import_pass!(execution_id, pass_id)
    row = channel.import_chats.create!(
      chat_id: 'legacy-worker@c.us', execution_id: execution_id, pass_id: pass_id,
      pass_number: 1, status: :importing, lease_token: nil, lease_expires_at: nil
    )
    channel.update_import_state!('phase' => 'importing')

    travel Waha::ImportChatWorkerJob::LEASE + 1.second do
      described_class.perform_now
    end

    expect(row.reload).to have_attributes(status: 'pending', attempts: 1, lease_token: nil)
  end

  it 'reenqueues an overdue settling pass after a deploy loses the delayed job' do
    channel.enqueue_history_import!(window, kind: 'initial')
    state = channel.reload.import_state
    channel.update_import_state!(
      'status' => 'running', 'phase' => 'settling', 'next_attempt_at' => 1.minute.ago.utc.iso8601
    )
    clear_enqueued_jobs

    expect { described_class.perform_now }
      .to have_enqueued_job(Waha::HistoryImportJob)
      .with(channel.id, window, 'initial', state.fetch('execution_id'), state.fetch('pass_id'))
  end

  it 'reclaims a dispatcher whose discovery lease expired after a crash' do
    channel.enqueue_history_import!(window, kind: 'initial')
    state = channel.reload.import_state
    channel.claim_import_pass!(state.fetch('execution_id'), state.fetch('pass_id'))
    channel.update_import_state!('dispatcher_lease_expires_at' => 1.minute.ago.utc.iso8601)
    clear_enqueued_jobs

    expect { described_class.perform_now }
      .to have_enqueued_job(Waha::HistoryImportJob)
      .with(channel.id, window, 'initial', state.fetch('execution_id'), state.fetch('pass_id'))
  end
end
