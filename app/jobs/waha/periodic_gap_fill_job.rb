class Waha::PeriodicGapFillJob < ApplicationJob
  queue_as :scheduled_jobs

  # Wider than the run interval in schedule.yml so two consecutive sweeps
  # always overlap and nothing can slip through the gap between them.
  WINDOW = 45.minutes

  # WAHA (GOWS engine) can silently drop live events under internal load, with
  # no session disconnect to trigger the existing reconnect gap-fill. This
  # periodic sweep is the safety net: it re-asks WAHA for each connected
  # channel's recent messages and lets the already-idempotent import path
  # (dedup by stanza id) fill in anything that never arrived live.
  def perform
    Channel::Waha.where(session_status: 'WORKING').find_each do |channel|
      next unless channel.account&.active?

      channel.enqueue_history_import!(window, kind: 'gap_fill')
    end
  end

  private

  def window
    { 'window_start' => WINDOW.ago.utc.iso8601, 'window_end' => Time.current.utc.iso8601 }
  end
end
