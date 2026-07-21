class Waha::HistoryImportJob < ApplicationJob
  queue_as :low

  MAX_RETRIES = 5
  THROTTLE = 0.5

  # Orchestrates a silent history import for one WAHA channel: it is the logical
  # lock (import_state.status == running), scans chats in scope, imports each one,
  # and persists progress so a failure resumes from the next un-processed chat.
  def perform(channel_id, window, kind)
    @channel = Channel::Waha.find_by(id: channel_id)
    return unless @channel

    @window = window
    @kind = kind
    @channel.start_import!(kind: kind, window: window) unless resuming?
    import_all_chats
    finalize
  rescue StandardError => e
    handle_failure(e)
  end

  private

  # A retry re-enqueues the same job while status is still running; that run
  # resumes (skips already-processed chats) instead of restarting the import.
  def resuming?
    state = @channel.import_state
    state['status'] == 'running' && state['kind'] == @kind &&
      state['window_start'] == @window['window_start'] && state['window_end'] == @window['window_end']
  end

  def import_all_chats
    chat_ids = Waha::ChatOverviewFetcher.new(channel: @channel).all
    @channel.set_import_total_chats!(chat_ids.size)
    processed = @channel.import_processed_chat_ids.to_set

    chat_ids.each { |chat_id| import_chat(chat_id) unless processed.include?(chat_id) }
  end

  def import_chat(chat_id)
    imported = Waha::ChatHistoryImporter.new(channel: @channel, chat_id: chat_id, window: @window).run
    @channel.mark_import_chat_processed!(chat_id, imported)
    sleep THROTTLE
  end

  # A gap-fill window that arrived while this import ran is picked up as a fresh
  # follow-up import; otherwise the import is done.
  def finalize
    queued = @channel.import_state['queued_window']
    if queued
      @channel.update_import_state!('queued_window' => nil, 'status' => 'pending')
      self.class.perform_later(@channel.id, queued, 'gap_fill')
    else
      @channel.finish_import!
    end
  end

  # Re-finds the channel so a mid-import inbox deletion just stops silently
  # instead of erroring on a gone record.
  def handle_failure(error)
    channel = Channel::Waha.find_by(id: @channel&.id)
    return if channel.nil?

    channel.record_import_retry!
    if channel.import_retries <= MAX_RETRIES
      self.class.set(wait: backoff(channel)).perform_later(channel.id, @window, @kind)
    else
      channel.fail_import!(error.message)
    end
  end

  # Quadratic backoff: 10s, 40s, 90s, 160s, 250s.
  def backoff(channel)
    ((channel.import_retries**2) * 10).seconds
  end
end
