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
    IMPORT_ACTIVE_STATES.include?(import_state['status'])
  end

  def import_retries
    import_state['retries'] || 0
  end

  # Aggregate progress for the UI, computed from the per-chat rows at read time so
  # the import hot path never rewrites the jsonb. Keys mirror the fields the
  # frontend reads off import_state.
  def import_progress
    done = WahaImportChat.statuses.values_at(:done, :failed)
    total, processed, imported = import_chats.pick(
      Arel.sql("COUNT(*), COUNT(*) FILTER (WHERE status IN (#{done.join(',')})), COALESCE(SUM(imported_count), 0)")
    )
    { 'total_chats' => total, 'processed_chats' => processed, 'imported_messages' => imported }
  end

  # The window currently being imported, as a string-keyed hash — the same shape
  # jobs pass around and the retry endpoint replays.
  def import_window
    { 'window_start' => import_state['window_start'], 'window_end' => import_state['window_end'] }
  end

  # The only transition into running. The scheduled claim and its execution token
  # are persisted before the job is put on the queue, so duplicate jobs can never
  # both seed or reclaim the same chat rows.
  def start_scheduled_import!(execution_id)
    with_lock do
      state = import_state
      if state['status'] == 'scheduled' && state['execution_id'] == execution_id
        update_import_state!('status' => 'running', 'started_at' => Time.current.utc.iso8601)
        execution_id
      elsif execution_id.blank? && state['status'] == 'pending'
        # Compatibility for a follow-up job enqueued by the pre-single-flight
        # implementation. All newly scheduled jobs always have a token.
        legacy_execution_id = SecureRandom.uuid
        update_import_state!('status' => 'running', 'execution_id' => legacy_execution_id, 'started_at' => Time.current.utc.iso8601)
        legacy_execution_id
      end
    end
  end

  def import_running_for?(execution_id)
    import_running? && import_execution_matches?(execution_id)
  end

  # Called by a dispatcher or worker after it finds no remaining work. The row
  # lock makes the drained check and terminal/follow-up transition one operation.
  def finalize_import_if_drained!(execution_id)
    request = with_lock do
      next unless import_running_for?(execution_id)
      next if import_chats.exists?(status: %i[pending importing])

      finalize_import!
    end
    enqueue_import_job!(request)
  end

  # GOWS can report a chat in the overview before that chat's own message
  # history has synced, so a first pass can legitimately find chats but zero
  # messages in every one of them. Retry the whole discovery+fetch cycle (same
  # budget as the empty-overview retry in Waha::HistoryImportJob) before
  # accepting "0 messages" as the real answer. A truly empty overview (no chats
  # at all) is already handled upstream by that same retry, so this only fires
  # once chats were actually found.
  def retry_empty_initial_import?
    import_state['kind'] == 'initial' && import_chats.exists? && import_progress['imported_messages'].to_i.zero? &&
      import_retries < Waha::HistoryImportJob::MAX_RETRIES
  end

  def retry_empty_initial_import!
    retries = import_retries + 1
    schedule_import!(
      kind: 'initial', window: import_window, clear_rows: true, retries: retries,
      queued_window: import_state['queued_window'], queued_kind: import_state['queued_kind'],
      wait: ((retries**2) * 30).seconds
    )
  end

  def finish_import!
    update_import_state!(
      'status' => 'completed', 'finished_at' => Time.current.utc.iso8601,
      'queued_window' => nil, 'queued_kind' => nil
    )
    observe_import_finished(:completed)
  end

  def fail_import!(message)
    update_import_state!(
      'status' => 'failed', 'error' => message.to_s.truncate(500), 'finished_at' => Time.current.utc.iso8601
    )
    observe_import_finished(:failed)
  end

  # Resumes a failed import from where it stopped, replaying the same window.
  # It receives a new scheduled execution token but preserves completed chat rows
  # and their cursors. Returns false (no-op) unless the import is currently failed.
  def retry_failed_import!
    request = with_lock do
      next unless import_state['status'] == 'failed'

      import_chats.where(status: %i[importing failed]).update_all(status: WahaImportChat.statuses[:pending])
      schedule_import!(
        kind: import_state['kind'], window: import_window, clear_rows: false,
        queued_window: import_state['queued_window'], queued_kind: import_state['queued_kind']
      )
    end
    enqueue_import_job!(request)
    request.present?
  end

  # A systemic dispatcher failure happens before any chat worker has claimed a
  # row. It gets a fresh scheduled token and preserves any seeded rows. If workers
  # are already active, they own the current state and are left alone to drain it.
  # rubocop:disable Metrics/MethodLength
  def retry_import_after_failure!(execution_id, message)
    request = nil
    outcome = with_lock do
      next unless import_running_for?(execution_id)

      retries = import_retries + 1
      if import_chats.importing.exists?
        update_import_state!('retries' => retries)
        { status: :running, retries: retries }
      elsif retries <= Waha::HistoryImportJob::MAX_RETRIES
        request = schedule_import!(
          kind: import_state['kind'], window: import_window, clear_rows: false, retries: retries,
          queued_window: import_state['queued_window'], queued_kind: import_state['queued_kind'],
          wait: ((retries**2) * 10).seconds
        )
        { status: :scheduled, retries: retries }
      else
        fail_import!(message)
        { status: :failed, retries: retries }
      end
    end
    enqueue_import_job!(request)
    outcome
  end
  # rubocop:enable Metrics/MethodLength

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
    started_at = import_state['started_at']
    progress = import_progress
    Waha::Telemetry.emit(
      :import_finished, channel: self, level: outcome == :failed ? :error : :info,
                        kind: import_state['kind'], execution_id: import_state['execution_id'], outcome: outcome,
                        duration_ms: (started_at && ((Time.current - Time.zone.parse(started_at)) * 1000).round),
                        chats: progress['total_chats'], imported_messages: progress['imported_messages'],
                        failed_chats: import_chats.failed.count
    )
  end

  # All callers hold the channel row lock. A fresh execution may remove old chat
  # rows only after the previous execution reached a terminal state; resumptions
  # keep their checkpoints intact.
  def schedule_import!(kind:, window:, clear_rows:, **options)
    retries = options.fetch(:retries, 0)
    queued_window, queued_kind, wait = options.values_at(:queued_window, :queued_kind, :wait)
    import_chats.delete_all if clear_rows

    execution_id = SecureRandom.uuid
    update_import_state!(
      'status' => 'scheduled', 'execution_id' => execution_id, 'kind' => kind,
      'window_start' => window['window_start'], 'window_end' => window['window_end'],
      'scheduled_at' => Time.current.utc.iso8601, 'started_at' => nil, 'finished_at' => nil,
      'error' => nil, 'retries' => retries, 'queued_window' => queued_window, 'queued_kind' => queued_kind
    )
    { execution_id: execution_id, kind: kind, wait: wait, window: window }
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

  # Called while holding the channel row lock after all pending/importing rows
  # have drained. It either creates the one permitted follow-up execution or
  # records the terminal state of the current one.
  def finalize_import!
    if import_chats.failed.exists?
      fail_import!(import_chats.failed.where.not(error: nil).pick(:error) || 'One or more chats failed to import')
      return
    end

    return retry_empty_initial_import! if retry_empty_initial_import?

    queued = import_state['queued_window']
    if queued
      schedule_import!(
        kind: import_state['queued_kind'] || 'gap_fill', window: queued, clear_rows: true
      )
    else
      finish_import!
      nil
    end
  end

  def import_execution_matches?(execution_id)
    return import_state['execution_id'].blank? if execution_id.blank?

    import_state['execution_id'] == execution_id
  end

  # Enqueue after the row-lock transaction commits so the job can always observe
  # the scheduled claim. If the adapter rejects it, turn that exact claim into a
  # terminal failure so a later trigger or the retry endpoint can recover.
  def enqueue_import_job!(request)
    return unless request

    job = request[:wait].nil? ? Waha::HistoryImportJob : Waha::HistoryImportJob.set(wait: request[:wait])
    job.perform_later(id, request[:window], request[:kind], request[:execution_id])
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
