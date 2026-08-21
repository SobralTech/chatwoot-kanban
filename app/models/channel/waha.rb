# == Schema Information
#
# Table name: channel_waha
#
#  id                        :bigint           not null, primary key
#  api_key                   :string           not null
#  auto_read_receipts        :boolean          default(TRUE), not null
#  auto_reconnect            :boolean          default(TRUE), not null
#  connected_number_locked   :boolean          default(FALSE), not null
#  groups_enabled            :boolean          default(FALSE), not null
#  import_on_connect_months  :integer
#  import_state              :jsonb            not null
#  phone_number              :string
#  session_name              :string           not null
#  session_status            :string
#  signing_enabled           :boolean          default(FALSE), not null
#  status_history            :jsonb
#  typing_simulation_enabled :boolean          default(TRUE), not null
#  waha_url                  :string           not null
#  webhook_token             :string           not null
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  account_id                :integer          not null
#
# Indexes
#
#  index_channel_waha_on_account_id     (account_id)
#  index_channel_waha_on_webhook_token  (webhook_token) UNIQUE
#
# Import/session bookkeeping is written with update_column(s) by design: these
# are high-frequency progress writes that must not fire validations, callbacks
# or broadcasts on the message hot path.
# rubocop:disable Rails/SkipsModelValidations
class Channel::Waha < ApplicationRecord
  include Channelable

  self.table_name = 'channel_waha'

  has_many :import_chats, class_name: 'WahaImportChat', foreign_key: :channel_waha_id,
                          dependent: :delete_all, inverse_of: :channel
  EDITABLE_ATTRS = [:phone_number, :waha_url, :api_key, :session_name,
                    :groups_enabled, :auto_reconnect, :auto_read_receipts, :typing_simulation_enabled,
                    :signing_enabled,
                    :import_on_connect_months].freeze

  # Cap on how far back any import window can reach, even after a very long outage.
  IMPORT_WINDOW_CAP = 6.months

  # Chats we never mirror into Chatwoot, in either the live or the import path.
  IGNORED_CHAT_SUFFIXES = %w[@newsletter status@broadcast].freeze

  before_validation :sanitize_session_name
  before_create :generate_webhook_token
  after_create :start_waha_session
  before_destroy :cleanup_waha_session
  validates :waha_url, :api_key, :session_name, presence: true

  def name
    'Waha'
  end

  def webhook_url
    "#{ENV.fetch('FRONTEND_URL', nil)}/webhooks/waha/#{webhook_token}"
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

  # --- Import state (single source of truth for progress + lock) ---

  # `status == "running"` is the logical lock: no new import starts while one runs.
  def import_running?
    import_state['status'] == 'running'
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

  # Begins a fresh import: clears any prior per-chat rows and resets the jsonb
  # header (the per-item progress now lives in import_chats). Only called when not
  # resuming, so wiping the rows is safe.
  def start_import!(kind:, window:)
    import_chats.delete_all
    update_import_state!(
      'status' => 'running', 'kind' => kind,
      'window_start' => window['window_start'], 'window_end' => window['window_end'],
      'started_at' => Time.current.utc.iso8601,
      'finished_at' => nil, 'error' => nil, 'retries' => 0, 'queued_window' => nil
    )
  end

  def record_import_retry!
    update_import_state!('retries' => import_retries + 1)
  end

  # Called by the last worker to drain the queue: a gap-fill window that arrived
  # mid-import is picked up as a follow-up run, otherwise the import is done.
  def finalize_import!
    queued = import_state['queued_window']
    if queued
      update_import_state!('queued_window' => nil, 'status' => 'pending')
      Waha::HistoryImportJob.perform_later(id, queued, 'gap_fill')
    else
      finish_import!
    end
  end

  def finish_import!
    update_import_state!('status' => 'done', 'finished_at' => Time.current.utc.iso8601, 'queued_window' => nil)
  end

  def fail_import!(message)
    update_import_state!('status' => 'failed', 'error' => message.to_s.truncate(500))
  end

  # Resumes a failed import from where it stopped, replaying the same window.
  # Restores the running lock (not pending) with a fresh retry budget so the
  # re-enqueued job resumes over the already-processed chats instead of
  # restarting. Returns false (no-op) unless the import is currently failed.
  def retry_failed_import!
    return false unless import_state['status'] == 'failed'

    import_chats.where(status: %i[importing failed]).update_all(status: WahaImportChat.statuses[:pending])
    update_import_state!('status' => 'running', 'error' => nil, 'retries' => 0)
    Waha::HistoryImportJob.perform_later(id, import_window, import_state['kind'])
    true
  end

  # A gap-fill window that arrives while an import is running is stashed as a
  # single pending window; subsequent windows merge by taking the widest span.
  def queue_import_window(window)
    existing = import_state['queued_window']
    merged = if existing
               { 'window_start' => [existing['window_start'], window['window_start']].min,
                 'window_end' => [existing['window_end'], window['window_end']].max }
             else
               window
             end
    update_import_state!('queued_window' => merged)
  end

  def update_import_state!(attrs)
    update_column(:import_state, import_state.merge(attrs.stringify_keys))
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

  def sanitize_session_name
    return if session_name.blank?

    self.session_name = session_name.strip.gsub(/[^a-zA-Z0-9._-]+/, '_')
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
# rubocop:enable Rails/SkipsModelValidations
