# == Schema Information
#
# Table name: channel_waha
#
#  id                           :bigint           not null, primary key
#  api_key                      :string           not null
#  auto_read_receipts           :boolean          default(TRUE), not null
#  auto_reconnect               :boolean          default(TRUE), not null
#  connected_number_locked      :boolean          default(FALSE), not null
#  connection_identity_conflict :boolean          default(FALSE), not null
#  groups_enabled               :boolean          default(FALSE), not null
#  import_on_connect_months     :integer
#  import_state                 :jsonb            not null
#  normalized_session_name      :string
#  normalized_waha_url          :string
#  phone_number                 :string
#  session_name                 :string           not null
#  session_status               :string
#  signing_enabled              :boolean          default(FALSE), not null
#  status_history               :jsonb
#  typing_simulation_enabled    :boolean          default(TRUE), not null
#  waha_url                     :string           not null
#  webhook_token                :string           not null
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  account_id                   :integer          not null
#
# Indexes
#
#  index_channel_waha_on_account_id           (account_id)
#  index_channel_waha_on_connection_identity  (normalized_waha_url,normalized_session_name) UNIQUE WHERE (connection_identity_conflict = false)
#  index_channel_waha_on_webhook_token        (webhook_token) UNIQUE
#
# Import/session bookkeeping is written with update_column(s) by design: these
# are high-frequency progress writes that must not fire validations, callbacks
# or broadcasts on the message hot path.
# rubocop:disable Rails/SkipsModelValidations, Metrics/ClassLength
class Channel::Waha < ApplicationRecord
  include Channelable

  self.table_name = 'channel_waha'

  has_many :import_chats, class_name: 'WahaImportChat', foreign_key: :channel_waha_id,
                          dependent: :delete_all, inverse_of: :channel
  has_many :message_mappings, class_name: 'WahaMessageMapping', foreign_key: :channel_waha_id,
                              dependent: :delete_all, inverse_of: :channel
  has_many :contact_aliases, class_name: 'WahaContactAlias', foreign_key: :channel_waha_id,
                             dependent: :delete_all, inverse_of: :channel
  has_many :delivery_attempts, class_name: 'WahaDeliveryAttempt', foreign_key: :channel_waha_id,
                               dependent: :delete_all, inverse_of: :channel
  EDITABLE_ATTRS = [:phone_number, :waha_url, :api_key, :session_name,
                    :groups_enabled, :auto_reconnect, :auto_read_receipts, :typing_simulation_enabled,
                    :signing_enabled,
                    :import_on_connect_months].freeze

  # Cap on how far back any import window can reach, even after a very long outage.
  IMPORT_WINDOW_CAP = 6.months

  before_validation :normalize_connection_identity
  before_create :generate_webhook_token
  after_create :start_waha_session
  before_destroy :cleanup_waha_session
  validates :waha_url, :api_key, :session_name, presence: true
  validate :waha_url_is_valid
  validate :connection_identity_is_unique

  def name
    'Waha'
  end

  def webhook_url
    "#{ENV.fetch('FRONTEND_URL', nil)}/webhooks/waha/#{webhook_token}"
  end

  def accepts_webhook_session?(session)
    normalized_session_name.present? && normalized_session_name == Waha::ConnectionIdentity.normalize_session_name(session)
  end

  def webhook_error(session)
    return connection_identity_error if connection_identity_conflict?
    return if accepts_webhook_session?(session)

    I18n.t('errors.messages.waha_webhook_session_mismatch')
  end

  def connection_identity_error
    I18n.t('errors.messages.waha_connection_conflict')
  end

  def update_session_status(status)
    update_columns(session_status: status, status_history: appended_history(status))
  end

  # Records an event in the connection log without touching session_status — used
  # for synthetic events (e.g. a blocked number mismatch) that aren't real WAHA
  # session states.
  def log_status_event(status)
    update_columns(status_history: appended_history(status))
  end

  # --- Import state (single source of truth for progress + single-flight lock) ---

  # `pending` is retained only so a job queued before this state machine was
  # deployed can finish. New imports use the four explicit states below.
  IMPORT_ACTIVE_STATES = %w[scheduled running pending].freeze

  def import_running?
    import_state['status'] == 'running'
  end

  def import_active?
    IMPORT_ACTIVE_STATES.include?(import_state['status']) || import_state['media_pending'] == true
  end

  def import_retries
    import_state['retries'] || 0
  end

  # Aggregate progress for the UI, computed from the per-chat rows at read time so
  # the import hot path never rewrites the jsonb. Keys mirror the fields the
  # frontend reads off import_state.
  def import_progress
    done = WahaImportChat.statuses.values_at(:done, :failed)
    total, processed, imported, discovered, failed = import_chats.pick(
      Arel.sql(
        "COUNT(*), COUNT(*) FILTER (WHERE status IN (#{done.join(',')})), COALESCE(SUM(imported_count), 0), " \
        'COALESCE(SUM(GREATEST(observed_message_count, pass_observed_message_count)), 0), ' \
        "COUNT(*) FILTER (WHERE status = #{WahaImportChat.statuses[:failed]})"
      )
    )
    progress = {
      'total_chats' => total, 'processed_chats' => processed, 'imported_messages' => imported,
      'discovered_messages' => discovered, 'failed_chats' => failed
    }
    next_chat_attempt = import_chats.pending.minimum(:next_attempt_at)
    progress['next_attempt_at'] = next_chat_attempt.utc.iso8601 if next_chat_attempt
    progress
  end

  # The window currently being imported, as a string-keyed hash — the same shape
  # jobs pass around and the retry endpoint replays.
  def import_window
    { 'window_start' => import_state['window_start'], 'window_end' => import_state['window_end'] }
  end

  # Claims the dispatcher lease for one exact execution/pass. This covers both
  # the first scheduled pass and later settling passes; a duplicate job or a job
  # carrying an older pass token cannot discover, reset, or dispatch work.
  def claim_import_pass!(execution_id, pass_id)
    with_lock do
      state = import_state
      next unless import_execution_matches?(execution_id) && import_pass_matches?(pass_id)
      next unless dispatcher_claimable?(state)

      now = Time.current
      token = SecureRandom.uuid
      update_import_state!(
        'status' => 'running', 'phase' => 'discovering', 'started_at' => state['started_at'] || now.utc.iso8601,
        'pass_started_at' => now.utc.iso8601, 'dispatcher_token' => token,
        'dispatcher_lease_expires_at' => Waha::HistoryImportJob::DISPATCHER_LEASE.from_now.utc.iso8601,
        'next_attempt_at' => nil
      )
      token
    end
  end

  # Compatibility for jobs that were already queued when pass tokens were
  # deployed. The channel lock assigns one token and adopts its existing rows;
  # every subsequent job follows the normal exact-token path.
  def ensure_import_pass_identity!(execution_id)
    with_lock do
      next unless import_execution_matches?(execution_id)
      next import_state['pass_id'] if import_state['pass_id'].present?

      pass_id = SecureRandom.uuid
      pass_number = import_state['pass_number'].to_i.clamp(1, Waha::HistoryImportJob::MAX_PASSES)
      import_chats.update_all(execution_id: execution_id, pass_id: pass_id, pass_number: pass_number)
      phase = import_state['phase'] || (import_running? ? 'importing' : 'scheduled')
      update_import_state!('pass_id' => pass_id, 'pass_number' => pass_number, 'phase' => phase)
      pass_id
    end
  end

  def import_running_for?(execution_id, pass_id = nil)
    import_running? && import_execution_matches?(execution_id) && (pass_id.nil? || import_pass_matches?(pass_id))
  end

  def begin_import_pass!(execution_id, pass_id, dispatcher_token, new_chats:)
    with_lock do
      next false unless dispatcher_owned?(execution_id, pass_id, dispatcher_token)

      attrs = {
        'phase' => 'importing', 'dispatcher_token' => nil, 'dispatcher_lease_expires_at' => nil,
        'pass_new_chats' => new_chats, 'pass_new_messages' => 0
      }
      attrs['last_growth_at'] = Time.current.utc.iso8601 if new_chats.positive?
      update_import_state!(attrs)
      true
    end
  end

  # Called by a dispatcher or worker after it finds no remaining work. The row
  # lock makes the drained check and terminal/follow-up transition one operation.
  def finalize_import_if_drained!(execution_id, pass_id = import_state['pass_id'])
    outcome = with_lock do
      next unless import_running_for?(execution_id, pass_id)

      rows = import_chats.for_pass(execution_id, pass_id)
      next if rows.exists?(status: %i[pending importing])

      finalize_import_pass!(rows)
    end
    enqueue_import_job!(outcome&.dig(:request))
    enqueue_media_dispatch!(outcome&.dig(:media_execution_id))
  end

  def finish_import!
    update_import_state!(
      'status' => 'completed', 'finished_at' => Time.current.utc.iso8601,
      'phase' => 'completed', 'failure_reason' => nil, 'next_attempt_at' => nil,
      'dispatcher_token' => nil, 'dispatcher_lease_expires_at' => nil,
      'media_pending' => import_state['kind'] == 'initial'
    )
    observe_import_finished(:completed)
  end

  def fail_import!(message, reason: nil)
    update_import_state!(
      'status' => 'failed', 'phase' => 'failed', 'error' => message.to_s.truncate(500),
      'failure_reason' => reason&.to_s, 'finished_at' => Time.current.utc.iso8601,
      'next_attempt_at' => nil, 'dispatcher_token' => nil, 'dispatcher_lease_expires_at' => nil,
      'media_pending' => import_state['kind'] == 'initial'
    )
    observe_import_finished(:failed)
  end

  # Resumes a failed import from where it stopped, replaying the same window.
  # It receives a new scheduled execution token but preserves completed chat rows
  # and their cursors. Returns false (no-op) unless the import is currently failed.
  def retry_failed_import!
    request = with_lock do
      next unless import_state['status'] == 'failed'
      next if import_state['media_pending'] == true

      restart = import_state['failure_reason'] == 'not_converged'
      schedule_import!(
        kind: import_state['kind'], window: import_window, clear_rows: restart, resume: !restart,
        queued_window: import_state['queued_window'], queued_kind: import_state['queued_kind']
      )
    end
    enqueue_import_job!(request)
    request.present?
  end

  def fail_import_dispatch!(execution_id, pass_id, dispatcher_token, error)
    outcome = with_lock do
      next unless dispatcher_owned?(execution_id, pass_id, dispatcher_token)

      fail_import!(error.message, reason: :dispatcher_terminal)
      { status: :failed, retries: import_retries, media_execution_id: execution_id }
    end
    enqueue_media_dispatch!(outcome&.dig(:media_execution_id))
    outcome
  end

  def retry_import_dispatch!(execution_id, pass_id, dispatcher_token, error)
    outcome = with_lock do
      next unless dispatcher_owned?(execution_id, pass_id, dispatcher_token)

      retry_import_dispatch_outcome(execution_id, error)
    end
    enqueue_import_job!(outcome&.dig(:request))
    enqueue_media_dispatch!(outcome&.dig(:media_execution_id))
    outcome
  end

  def retry_import_dispatch_outcome(execution_id, error)
    retries = import_retries + 1
    wait = ((retries**2) * 10).seconds
    return fail_not_converged!(:settling_timeout).merge(status: :failed, retries: retries) if initial_import_deadline_exceeded?(wait.from_now)

    if retries <= Waha::HistoryImportJob::MAX_RETRIES
      update_import_state!(
        'phase' => 'settling', 'retries' => retries, 'next_attempt_at' => wait.from_now.utc.iso8601,
        'dispatcher_token' => nil, 'dispatcher_lease_expires_at' => nil, 'error' => error.message.to_s.truncate(500)
      )
      { status: :scheduled, retries: retries, request: current_pass_request(wait: wait) }
    else
      fail_import!(error.message, reason: :dispatcher_retries_exhausted)
      { status: :failed, retries: retries, media_execution_id: execution_id }
    end
  end

  # Repairs queue loss and expired leases from a process crash or deploy. Every
  # returned job still carries the persisted execution/pass token, so the
  # reconciler may safely overlap a delayed job already present in Sidekiq.
  def reconcile_import!
    outcome = with_lock do
      state = import_state
      if state['media_pending'] == true
        { media_execution_id: state['execution_id'] }
      elsif state['status'] == 'scheduled' || %w[settling discovering].include?(state['phase'])
        reconcile_dispatcher(state)
      elsif import_running? && state['phase'] == 'importing'
        reconcile_workers(state)
      end
    end
    enqueue_import_job!(outcome&.dig(:request))
    enqueue_worker_jobs!(outcome&.dig(:workers).to_i, outcome&.dig(:worker_request))
    enqueue_media_dispatch!(outcome&.dig(:media_execution_id))
    outcome
  end

  def complete_media_dispatch!(execution_id)
    request = with_lock do
      next unless import_execution_matches?(execution_id) && import_state['media_pending'] == true

      update_import_state!('media_pending' => false, 'media_dispatched_at' => Time.current.utc.iso8601)
      queued = import_state['queued_window']
      next unless import_state['status'] == 'completed' && queued

      schedule_import!(kind: import_state['queued_kind'] || 'gap_fill', window: queued, clear_rows: true)
    end
    enqueue_import_job!(request)
  end

  def update_import_state!(attrs)
    update_column(:import_state, import_state.merge(attrs.stringify_keys))
  end

  # Starts a history import for this channel, or — respecting the
  # single-import-per-channel lock — merges the window into the one already
  # running. Shared by the webhook-triggered opt-in import/reconnect gap-fill
  # and the periodic safety-net sweep (Waha::PeriodicGapFillJob).
  def enqueue_history_import!(window, kind:)
    request = with_lock do
      if import_active?
        queue_import_window!(window, kind) unless current_import_covers?(window, kind)
        nil
      else
        schedule_import!(
          kind: kind, window: window, clear_rows: true,
          wait: kind == 'initial' ? Waha::HistoryImportJob::INITIAL_DELAY : nil
        )
      end
    end
    enqueue_import_job!(request)
    request.present?
  end

  # --- Import windows ---

  # Consumed once, on the first WORKING connection, to kick off the opt-in import.
  def consume_import_on_connect_months!
    months = import_on_connect_months
    return if months.blank?

    update!(import_on_connect_months: nil)
    months
  end

  def initial_import_window(months)
    { 'window_start' => months.to_i.months.ago.utc.iso8601, 'window_end' => Time.current.utc.iso8601 }
  end

  # Window for a reconnect gap-fill: from midnight (account timezone) of the day
  # the session dropped, capped at IMPORT_WINDOW_CAP. Nil on the first connection
  # (no prior outage to fill).
  def gap_fill_window
    disconnect_at = last_outage_started_at
    return if disconnect_at.blank?

    window_start = [disconnect_at.in_time_zone(import_timezone).beginning_of_day, IMPORT_WINDOW_CAP.ago].max
    { 'window_start' => window_start.utc.iso8601, 'window_end' => Time.current.utc.iso8601 }
  end

  private

  # Both terminal transitions of an import are the same signal, separated by
  # `outcome`, so how long a channel takes to catch up is one series regardless
  # of whether it succeeded. `failed_chats` is what remains stuck; the failure
  # text stays in import_state and on the chat rows, out of the signal.
  def observe_import_finished(outcome)
    progress = import_progress
    Waha::Telemetry.emit(
      :import_finished, channel: self, level: outcome == :failed ? :error : :info,
                        **import_finished_context(outcome, progress)
    )
  end

  def import_finished_context(outcome, progress)
    {
      kind: import_state['kind'], execution_id: import_state['execution_id'], outcome: outcome,
      pass: import_state['pass_number'], pass_id: import_state['pass_id'], duration_ms: import_duration_ms,
      chats: progress['total_chats'], imported_messages: progress['imported_messages'],
      discovered_messages: progress['discovered_messages'], failed_chats: import_chats.failed.count,
      stable_passes: import_state['stable_passes'], reason: import_state['failure_reason']
    }
  end

  def import_duration_ms
    started_at = import_state['started_at']
    ((Time.current - Time.zone.parse(started_at)) * 1000).round if started_at
  end

  # All callers hold the channel row lock. A fresh execution may remove old chat
  # rows only after the previous execution reached a terminal state; resumptions
  # keep their checkpoints intact.
  def schedule_import!(kind:, window:, clear_rows:, resume: false, **options)
    queued_window, queued_kind, wait = options.values_at(:queued_window, :queued_kind, :wait)
    import_chats.delete_all if clear_rows

    execution_id = SecureRandom.uuid
    pass_id = SecureRandom.uuid
    pass_number = resume ? import_state['pass_number'].to_i.clamp(1, Waha::HistoryImportJob::MAX_PASSES) : 1
    prepare_resumed_rows!(execution_id, pass_id, pass_number) if resume
    now = Time.current
    state_options = {
      kind: kind, window: window, execution_id: execution_id, pass_id: pass_id, pass_number: pass_number,
      retries: options.fetch(:retries, 0), queued_window: queued_window, queued_kind: queued_kind, wait: wait, now: now
    }
    update_import_state!(scheduled_import_state(state_options))
    { execution_id: execution_id, pass_id: pass_id, kind: kind, wait: wait, window: window }
  end

  def scheduled_import_state(options)
    kind, window, execution_id, pass_id, pass_number = options.values_at(:kind, :window, :execution_id, :pass_id, :pass_number)
    retries, queued_window, queued_kind, wait, now = options.values_at(:retries, :queued_window, :queued_kind, :wait, :now)
    {
      'status' => 'scheduled', 'phase' => 'scheduled', 'execution_id' => execution_id,
      'pass_id' => pass_id, 'pass_number' => pass_number, 'kind' => kind,
      'window_start' => window['window_start'], 'window_end' => window['window_end'],
      'scheduled_at' => now.utc.iso8601, 'started_at' => nil, 'finished_at' => nil,
      'pass_started_at' => nil, 'last_growth_at' => now.utc.iso8601,
      'next_attempt_at' => wait ? wait.from_now.utc.iso8601 : now.utc.iso8601,
      'stable_passes' => 0, 'pass_new_chats' => 0, 'pass_new_messages' => 0,
      'error' => nil, 'failure_reason' => nil, 'not_converged_reason' => nil, 'retries' => retries,
      'dispatcher_token' => nil, 'dispatcher_lease_expires_at' => nil,
      'media_pending' => false, 'queued_window' => queued_window, 'queued_kind' => queued_kind
    }
  end

  def prepare_resumed_rows!(execution_id, pass_id, pass_number)
    attrs = {
      execution_id: execution_id, pass_id: pass_id, pass_number: pass_number,
      lease_token: nil, lease_expires_at: nil, next_attempt_at: nil
    }
    import_chats.update_all(attrs)
    import_chats.where(status: %i[importing failed]).update_all(
      status: WahaImportChat.statuses[:pending], attempts: 0, error: nil
    )
  end

  # Called while holding the channel row lock. A single coalesced follow-up keeps
  # the channel single-flight; initial imports take precedence so the opt-in
  # backfill is not lost if it races a gap-fill trigger.
  def queue_import_window!(window, kind)
    existing = import_state['queued_window']
    merged = if existing
               { 'window_start' => [existing['window_start'], window['window_start']].min,
                 'window_end' => [existing['window_end'], window['window_end']].max }
             else
               window
             end
    queued_kind = import_state['queued_kind'] || 'gap_fill'
    queued_kind = 'initial' if queued_kind == 'initial' || kind == 'initial'
    update_import_state!('queued_window' => merged, 'queued_kind' => queued_kind)
  end

  # Repeated delivery of the same trigger is not follow-up work. Initial imports
  # are one-time by definition; a gap-fill only needs another execution when its
  # window extends beyond the current gap-fill's confirmed range.
  def current_import_covers?(window, kind)
    current_kind = import_state['kind']
    return true if kind == 'initial' && current_kind == 'initial'
    return false unless current_kind == kind

    current_window = import_window
    current_window['window_start'] <= window['window_start'] && current_window['window_end'] >= window['window_end']
  end

  def finalize_import_pass!(rows)
    if rows.failed.exists?
      fail_import!(rows.failed.where.not(error: nil).pick(:error) || 'One or more chats failed to import', reason: :chat_failed)
      return { media_execution_id: deferred_media_execution_id }
    end

    return finish_single_pass_import! unless import_state['kind'] == 'initial'

    advance_initial_convergence!(rows)
  end

  def finish_single_pass_import!
    finish_import!
    queued = import_state['queued_window']
    return {} unless queued

    request = schedule_import!(kind: import_state['queued_kind'] || 'gap_fill', window: queued, clear_rows: true)
    { request: request }
  end

  # A completed pass compares the canonical set observed for every chat with the
  # preceding pass, then advances the baseline. The rows themselves are the
  # persisted union of chats: scheduling a later pass resets only pass-local
  # cursor/work fields, never the rows or their prior fingerprints.
  def advance_initial_convergence!(rows)
    observation = pass_observation(rows)
    stable_passes = observation[:changed] ? 0 : import_state['stable_passes'].to_i + 1
    now = Time.current
    last_growth_at = pass_last_growth_at(observation[:message_growth], now)
    persist_pass_observation!(rows, stable_passes, observation[:message_growth], last_growth_at)
    observe_import_pass_finished(observation, stable_passes)

    return complete_converged_import! if stable_passes >= 2 && now - last_growth_at >= Waha::HistoryImportJob::QUIET_PERIOD
    return fail_not_converged!(convergence_limit(now)) if convergence_limit(now)

    schedule_next_pass!(last_growth_at)
  end

  def pass_observation(rows)
    changed = rows.where(
      'discovered_pass = pass_number OR observed_message_count <> pass_observed_message_count OR ' \
      'observed_message_digest IS DISTINCT FROM pass_observed_message_digest'
    ).exists?
    { changed: changed, message_growth: rows.sum('GREATEST(pass_observed_message_count - observed_message_count, 0)') }
  end

  def pass_last_growth_at(message_growth, now)
    return now if message_growth.positive?

    Time.zone.parse(import_state['last_growth_at'] || import_state['started_at'] || now.utc.iso8601)
  end

  def persist_pass_observation!(rows, stable_passes, message_growth, last_growth_at)
    rows.update_all(
      'observed_message_count = pass_observed_message_count, ' \
      'observed_message_digest = pass_observed_message_digest, updated_at = NOW()'
    )
    update_import_state!(
      'stable_passes' => stable_passes, 'pass_new_messages' => message_growth,
      'last_growth_at' => last_growth_at.utc.iso8601
    )
  end

  def observe_import_pass_finished(observation, stable_passes)
    Waha::Telemetry.emit(
      :import_pass_finished, channel: self, level: :info, kind: import_state['kind'],
                             execution_id: import_state['execution_id'], pass: import_state['pass_number'],
                             pass_id: import_state['pass_id'], outcome: observation[:changed] ? :grew : :stable,
                             new_chats: import_state['pass_new_chats'], new_messages: observation[:message_growth],
                             stable_passes: stable_passes
    )
  end

  def convergence_limit(now)
    return :max_passes if import_state['pass_number'].to_i >= Waha::HistoryImportJob::MAX_PASSES
    return :settling_timeout if settling_deadline <= now
  end

  def complete_converged_import!
    execution_id = import_state['execution_id']
    finish_import!
    { media_execution_id: execution_id }
  end

  def fail_not_converged!(limit)
    execution_id = import_state['execution_id']
    fail_import!("WAHA history did not converge before the #{limit} limit", reason: :not_converged)
    update_import_state!('not_converged_reason' => limit.to_s)
    Waha::Telemetry.emit(
      :import_not_converged, channel: self, level: :error, kind: import_state['kind'],
                             execution_id: execution_id, reason: limit, pass: import_state['pass_number']
    )
    { media_execution_id: execution_id }
  end

  def deferred_media_execution_id
    import_state['execution_id'] if import_state['kind'] == 'initial'
  end

  def schedule_next_pass!(last_growth_at)
    pass_number = import_state['pass_number'].to_i + 1
    pass_id = SecureRandom.uuid
    next_at = [Waha::HistoryImportJob::PASS_INTERVAL.from_now,
               last_growth_at + Waha::HistoryImportJob::QUIET_PERIOD].max
    return fail_not_converged!(:settling_timeout) if next_at > settling_deadline

    reset_rows_for_pass!(pass_id, pass_number)
    update_import_state!(
      'phase' => 'settling', 'pass_id' => pass_id, 'pass_number' => pass_number,
      'next_attempt_at' => next_at.utc.iso8601, 'pass_started_at' => nil,
      'pass_new_chats' => 0, 'pass_new_messages' => 0, 'retries' => 0,
      'dispatcher_token' => nil, 'dispatcher_lease_expires_at' => nil
    )
    { request: current_pass_request(wait: next_at - Time.current) }
  end

  def reset_rows_for_pass!(pass_id, pass_number)
    import_chats.update_all(
      status: WahaImportChat.statuses[:pending], execution_id: import_state['execution_id'],
      pass_id: pass_id, pass_number: pass_number, cursor: nil, cursor_message_id: nil,
      pass_imported_count: 0, pass_observed_message_count: 0, pass_observed_message_digest: nil,
      attempts: 0, next_attempt_at: nil, lease_token: nil, lease_expires_at: nil, error: nil
    )
  end

  def settling_deadline
    started_at = import_state['started_at'] || import_state['scheduled_at'] || Time.current.utc.iso8601
    Time.zone.parse(started_at) + Waha::HistoryImportJob::MAX_SETTLING_TIME
  end

  def current_pass_request(wait: nil)
    {
      execution_id: import_state['execution_id'], pass_id: import_state['pass_id'], kind: import_state['kind'],
      wait: wait, window: import_window
    }
  end

  def reconcile_dispatcher(state)
    return fail_not_converged!(:settling_timeout) if initial_import_deadline_exceeded?

    due_at = state['phase'] == 'discovering' ? state['dispatcher_lease_expires_at'] : state['next_attempt_at']
    return if due_at.present? && Time.zone.parse(due_at) > Time.current

    { request: current_pass_request }
  end

  def reconcile_workers(state)
    rows = import_chats.for_pass(state['execution_id'], state['pass_id'])
    reclaimed = rows.reclaim_expired!(
      channel_id: id, execution_id: state['execution_id'], pass_id: state['pass_id'],
      max_attempts: Waha::ImportChatWorkerJob::MAX_RETRIES,
      legacy_stale_before: Waha::ImportChatWorkerJob::LEASE.ago
    )
    observe_reclaimed_leases(state, reclaimed)

    return finalize_import_pass!(rows) unless rows.exists?(status: %i[pending importing])
    return fail_not_converged!(:settling_timeout) if initial_import_deadline_exceeded? && !rows.importing.exists?
    return if rows.importing.exists?

    pending_count = rows.claimable.count
    return if pending_count.zero?

    {
      workers: pending_count.clamp(1, Waha::HistoryImportJob::WORKER_POOL),
      worker_request: current_pass_request
    }
  end

  def observe_reclaimed_leases(state, reclaimed)
    return unless reclaimed.values.any?(&:positive?)

    Waha::Telemetry.emit(
      :import_leases_reconciled, channel: self, level: reclaimed[:failed].positive? ? :error : :warn,
                                 kind: state['kind'], execution_id: state['execution_id'], pass: state['pass_number'],
                                 pass_id: state['pass_id'], outcome: reclaimed[:failed].positive? ? :failed : :reclaimed,
                                 reclaimed: reclaimed[:reclaimed], failed: reclaimed[:failed]
    )
  end

  def import_execution_matches?(execution_id)
    return import_state['execution_id'].blank? if execution_id.blank?

    import_state['execution_id'] == execution_id
  end

  def import_pass_matches?(pass_id)
    return import_state['pass_id'].blank? if pass_id.blank?

    import_state['pass_id'] == pass_id
  end

  def dispatcher_claimable?(state)
    return true if %w[scheduled pending].include?(state['status'])
    return false unless state['status'] == 'running'
    return Time.zone.parse(state['next_attempt_at']) <= Time.current if state['phase'] == 'settling'
    return false unless state['phase'] == 'discovering'

    expires_at = state['dispatcher_lease_expires_at']
    expires_at.blank? || Time.zone.parse(expires_at) <= Time.current
  end

  def dispatcher_owned?(execution_id, pass_id, dispatcher_token)
    import_running_for?(execution_id, pass_id) && import_state['phase'] == 'discovering' &&
      import_state['dispatcher_token'] == dispatcher_token
  end

  def initial_import_deadline_exceeded?(time = Time.current)
    import_state['kind'] == 'initial' && settling_deadline <= time
  end

  # Enqueue after the row-lock transaction commits so the job can always observe
  # the scheduled claim. If the adapter rejects it, turn that exact claim into a
  # terminal failure so a later trigger or the retry endpoint can recover.
  def enqueue_import_job!(request)
    return unless request

    job = request[:wait].nil? ? Waha::HistoryImportJob : Waha::HistoryImportJob.set(wait: request[:wait])
    job.perform_later(id, request[:window], request[:kind], request[:execution_id], request[:pass_id])
  rescue StandardError => e
    fail_scheduled_import!(request[:execution_id], e.message)
    raise
  end

  def fail_scheduled_import!(execution_id, message)
    with_lock do
      next unless import_state['status'] == 'scheduled' && import_execution_matches?(execution_id)

      fail_import!(message)
    end
  end

  def enqueue_media_dispatch!(execution_id)
    return if execution_id.blank?

    Waha::HistoryMediaDispatchJob.perform_later(id, execution_id)
  end

  def enqueue_worker_jobs!(count, request)
    return if count.zero? || request.blank?

    count.times do
      Waha::ImportChatWorkerJob.perform_later(
        id, request[:window], request[:kind], request[:execution_id], request[:pass_id]
      )
    end
  end

  def import_timezone
    ActiveSupport::TimeZone[account.reporting_timezone.presence || 'UTC'] || ActiveSupport::TimeZone['UTC']
  end

  # The first non-WORKING transition after the previous WORKING — i.e. when the
  # outage that just ended began. Assumes the current WORKING is already logged
  # (last entry). Nil when there's no earlier WORKING (first ever connection).
  def last_outage_started_at
    history = status_history
    working_indices = history.each_index.select { |i| history[i]['status'] == 'WORKING' }
    return if working_indices.size < 2

    first_drop = history[working_indices[-2] + 1]
    # Nil or another WORKING means no real outage between the two connections.
    return if first_drop.nil? || first_drop['status'] == 'WORKING'

    Time.zone.parse(first_drop['timestamp'])
  end

  def appended_history(status)
    (status_history + [{ status: status, timestamp: Time.current.iso8601 }]).last(100)
  end

  def normalize_connection_identity
    normalized_url = Waha::ConnectionIdentity.normalize_url(waha_url)
    normalized_name = Waha::ConnectionIdentity.normalize_session_name(session_name)

    self.waha_url = normalized_url if normalized_url
    self.session_name = normalized_name if normalized_name
    self.normalized_waha_url = normalized_url
    self.normalized_session_name = normalized_name
    self.connection_identity_conflict = false if persisted? && connection_identity_changed?
  end

  def waha_url_is_valid
    return if waha_url.blank? || normalized_waha_url.present?

    errors.add(:waha_url, :waha_url_invalid)
  end

  def connection_identity_is_unique
    return if connection_identity_conflict? || normalized_waha_url.blank? || normalized_session_name.blank?

    existing_channel = self.class.where(
      normalized_waha_url: normalized_waha_url,
      normalized_session_name: normalized_session_name
    ).where.not(id: id).exists?
    errors.add(:base, :waha_connection_in_use) if existing_channel
  end

  def connection_identity_changed?
    will_save_change_to_normalized_waha_url? || will_save_change_to_normalized_session_name?
  end

  def generate_webhook_token
    self.webhook_token = SecureRandom.uuid
  end

  def start_waha_session
    Waha::SessionService.new(channel: self).start
  end

  def cleanup_waha_session
    Waha::SessionService.new(channel: self).delete_session
  end
end
# rubocop:enable Rails/SkipsModelValidations, Metrics/ClassLength
