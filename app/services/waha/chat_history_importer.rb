class Waha::ChatHistoryImporter
  # Pagination fetches text only (downloadMedia=false) — media is downloaded
  # later, off the critical path, via Waha::HistoryMediaJob. Without the inline
  # media download each page is light, so we can pull a large batch per request.
  PAGE_SIZE = 200

  FULL_WINDOW_MEDIA_KINDS = %w[image audio ptt sticker].freeze
  # Videos, documents and unknown media remain bounded because older WhatsApp
  # files are commonly expired and expensive to probe. Keep the existing env key
  # backwards compatible for installations that already tune the 30-day window.
  RECENT_MEDIA_MAX_AGE = ENV.fetch('WAHA_IMPORT_MEDIA_MAX_AGE_DAYS', 30).to_i.days

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
    @media_message_ids = Set.new(import_chat.media_message_ids)
    cursor = resume_cursor
    loop do
      page = fetch_page(cursor)
      break if page.blank?

      @conversation ||= resolve_conversation(page)
      return imported unless @conversation

      @existing_messages ||= load_existing_messages
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
    import_chat.update!(
      cursor: page.last['timestamp'].to_i,
      imported_count: import_chat.imported_count + imported,
      media_message_ids: @media_message_ids.to_a
    )
    imported
  end

  def write_message(payload)
    stanza = Waha::Anchoring.stanza_of(payload['id'])
    return false if stanza.blank?

    existing_message_id = @existing_messages[stanza]
    if existing_message_id
      track_media(existing_message_id, payload)
      return false
    end

    message = Waha::HistoryMessageWriter.new(channel: channel, payload: payload, conversation: @conversation).perform
    @existing_messages[stanza] = message.id
    track_timestamp(payload['timestamp'].to_i)
    track_media(message.id, payload)
    true
  end

  def track_media(message_id, payload)
    @media_message_ids << message_id if downloadable_media?(payload)
  end

  # Images, audio and stickers follow the full import window. Videos, documents
  # and unknown media keep the bounded recent-media window.
  def downloadable_media?(payload)
    return false if payload['hasMedia'].blank?

    kind = Waha::MediaAttacher.new(channel: channel, payload: payload).media_kind
    FULL_WINDOW_MEDIA_KINDS.include?(kind) || payload['timestamp'].to_i >= media_cutoff
  end

  def media_cutoff
    @media_cutoff ||= RECENT_MEDIA_MAX_AGE.ago.to_i
  end

  # One serial media job per chat (not per page): it fetches this chat's media
  # off the critical path, throttled and with a circuit breaker, so media never
  # floods the queue or hammers the WAHA session.
  def enqueue_media
    return if @media_message_ids.blank?

    Waha::HistoryMediaJob.perform_later(channel.id, chat_id, @media_message_ids.to_a)
  end

  def resolve_conversation(page)
    # Prefer an incoming sample: it carries the contact's real number/name for
    # @lid resolution (a fromMe sample only has our own side).
    sample = page.find { |message| !message['fromMe'] } || page.first
    contact_inbox = Waha::ContactResolver.from_payload(channel: channel, jid: chat_id, payload: sample).perform
    return unless contact_inbox

    # An import runs alongside live traffic, so the same chat can be resolved here
    # and by an inbound webhook at the same time. Both would find no conversation
    # and create one; the contact_inbox row serializes them.
    ::Conversation.transaction do
      contact_inbox.lock!
      contact_inbox.conversations.last || create_conversation(contact_inbox)
    end
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

  def load_existing_messages
    @conversation.messages.where.not(source_id: nil)
                 .pluck(:id, :source_id)
                 .to_h { |id, source_id| [Waha::Anchoring.stanza_of(source_id), id] }
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
    }.to_query

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
