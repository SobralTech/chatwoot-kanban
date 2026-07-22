class Waha::ChatHistoryImporter
  # Pagination fetches text only (downloadMedia=false) — media is downloaded
  # later, off the critical path, via Waha::HistoryMediaJob. Without the inline
  # media download each page is light, so we can pull a large batch per request.
  PAGE_SIZE = 200

  # Only media newer than this is worth fetching: older WhatsApp media (especially
  # in groups) is usually expired on the servers, so attempting it just burns a
  # 30s timeout per message and pounds the WAHA session for nothing.
  MEDIA_MAX_AGE = ENV.fetch('WAHA_IMPORT_MEDIA_MAX_AGE_DAYS', 30).to_i.days

  pattr_initialize [:channel!, :chat_id!, :window!, :import_chat!]

  # Imports one chat's messages within the window. Resolves the conversation once,
  # batch-dedups against existing stanza ids, then writes each new message
  # silently (backdated + read). Returns the number of messages written.
  # Best-effort: only what WhatsApp synced to the device is available.
  def run
    imported = import_messages
    finalize_conversation if imported.positive?
    enqueue_media
    imported
  end

  private

  # Cursor-based pagination by timestamp (not offset, which some WAHA engines
  # ignore — an ignored offset would re-fetch the same page forever). Each page
  # advances the lower bound to its last message's timestamp; the guard stops if
  # it can't advance. Progress + cursor are persisted per page so the UI advances
  # inside a large chat and a restart resumes mid-chat.
  def import_messages
    imported = 0
    @media_message_ids = []
    cursor = resume_cursor
    loop do
      page = fetch_page(cursor)
      break if page.blank?

      @conversation ||= resolve_conversation(page)
      return imported unless @conversation

      @existing_stanzas ||= load_existing_stanzas
      imported += write_page(page)
      break if page.size < PAGE_SIZE

      next_cursor = page.last['timestamp'].to_i
      break if next_cursor <= cursor

      cursor = next_cursor
    end
    imported
  end

  # Resume from the row's persisted cursor after a restart; otherwise start at the
  # window's lower bound.
  def resume_cursor
    import_chat.cursor || window_unix('window_start')
  end

  # Per-page progress on the chat's own row (single-row write, no jsonb churn):
  # bumps its imported count and persists the timestamp cursor for mid-chat resume.
  def write_page(page)
    imported = page.count { |payload| write_message(payload) }
    import_chat.update!(cursor: page.last['timestamp'].to_i, imported_count: import_chat.imported_count + imported)
    imported
  end

  def write_message(payload)
    stanza = payload['id'].to_s.split('_').last
    return false if stanza.blank? || @existing_stanzas.include?(stanza)

    message = Waha::HistoryMessageWriter.new(channel: channel, payload: payload, conversation: @conversation).perform
    @existing_stanzas << stanza
    track_timestamp(payload['timestamp'].to_i)
    @media_message_ids << message.id if downloadable_media?(payload)
    true
  end

  # Skip media that is almost certainly expired on WhatsApp's servers, so the
  # media job doesn't waste a 30s fetch (and WAHA load) on it.
  def downloadable_media?(payload)
    payload['hasMedia'].present? && payload['timestamp'].to_i >= media_cutoff
  end

  def media_cutoff
    @media_cutoff ||= MEDIA_MAX_AGE.ago.to_i
  end

  # One serial media job per chat (not per page): it fetches this chat's media
  # off the critical path, throttled and with a circuit breaker, so media never
  # floods the queue or hammers the WAHA session.
  def enqueue_media
    return if @media_message_ids.blank?

    Waha::HistoryMediaJob.perform_later(channel.id, chat_id, @media_message_ids)
  end

  def resolve_conversation(page)
    # Prefer an incoming sample: it carries the contact's real number/name for
    # @lid resolution (a fromMe sample only has our own side).
    sample = page.find { |message| !message['fromMe'] } || page.first
    contact_inbox = Waha::ContactResolver.new(
      channel: channel,
      jid: chat_id,
      push_name: sample.dig('_data', 'Info', 'PushName').presence || sample.dig('_data', 'pushName'),
      from_me: sample['fromMe'],
      sender_alt: sample.dig('_data', 'Info', 'SenderAlt'),
      recipient_alt: sample.dig('_data', 'Info', 'RecipientAlt')
    ).perform
    return unless contact_inbox

    contact_inbox.conversations.last || create_conversation(contact_inbox)
  end

  def create_conversation(contact_inbox)
    conversation = ::Conversation.new(
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      contact_id: contact_inbox.contact_id,
      contact_inbox_id: contact_inbox.id
    )
    conversation.imported = true
    conversation.save!
    conversation
  end

  def load_existing_stanzas
    @conversation.messages.where.not(source_id: nil)
                 .pluck(:source_id)
                 .to_set { |source_id| source_id.to_s.split('_').last }
  end

  def track_timestamp(unix)
    return if unix.zero?

    @min_ts = unix if @min_ts.nil? || unix < @min_ts
    @max_ts = unix if @max_ts.nil? || unix > @max_ts
  end

  # Imported conversations land resolved and read (no unread badges), with their
  # activity/creation timestamps extended to span the imported history. Written
  # via update_columns to stay silent (no status-change events/automation).
  def finalize_conversation
    now = Time.current
    # rubocop:disable Rails/SkipsModelValidations
    @conversation.update_columns(
      status: ::Conversation.statuses[:resolved],
      last_activity_at: [@conversation.last_activity_at, Time.zone.at(@max_ts)].compact.max,
      created_at: [@conversation.created_at, Time.zone.at(@min_ts)].compact.min,
      agent_last_seen_at: now,
      assignee_last_seen_at: now
    )
    # rubocop:enable Rails/SkipsModelValidations
  end

  def fetch_page(cursor)
    query = {
      'limit' => PAGE_SIZE,
      'sortBy' => 'timestamp', 'sortOrder' => 'asc', 'downloadMedia' => false,
      'filter.timestamp.gte' => cursor,
      'filter.timestamp.lte' => window_unix('window_end')
    }.map { |key, value| "#{key}=#{value}" }.join('&')

    response = http_client.get("#{channel.session_name}/chats/#{chat_id}/messages?#{query}")
    response.is_a?(Array) ? response : []
  end

  def window_unix(key)
    Time.zone.parse(window[key]).to_i
  end

  def inbox
    @inbox ||= channel.inbox
  end

  def http_client
    @http_client ||= Waha::HttpClient.new(channel: channel)
  end
end
