# rubocop:disable Metrics/ClassLength
class Waha::ChatHistoryImporter
  # Pagination fetches text only (downloadMedia=false) — media is downloaded
  # later, off the critical path, via Waha::HistoryMediaJob. Without the inline
  # media download each page is light, so we can pull a large batch per request.
  PAGE_SIZE = 200

  # GOWS exposes only a single sort/filter field (timestamp, second-resolution),
  # no documented tie-break and no reliable offset support (see SPEC.md). When a
  # whole page shares one timestamp, we can't tell if that's the entire
  # same-second cluster or just the first PAGE_SIZE of a larger one, so we
  # re-fetch that second alone with a much larger limit to resolve it in one
  # shot — bounding how large a cluster we can fully resolve in one page.
  MAX_TIED_SECOND_SIZE = PAGE_SIZE * 10

  FULL_WINDOW_MEDIA_KINDS = %w[image audio ptt sticker].freeze
  # Videos, documents and unknown media remain bounded because older WhatsApp
  # files are commonly expired and expensive to probe. Keep the existing env key
  # backwards compatible for installations that already tune the 30-day window.
  RECENT_MEDIA_MAX_AGE = ENV.fetch('WAHA_IMPORT_MEDIA_MAX_AGE_DAYS', 30).to_i.days

  pattr_initialize [:channel!, :chat_id!, :window!, :import_chat!, { kind: 'initial' }]

  # Imports one chat's messages within the window. Resolves the conversation once,
  # batch-dedups against existing stanza ids, then writes each new message using
  # the semantics of its import kind. Initial history stays silent and pre-read;
  # recent gap recovery remains actionable. Returns the number of messages written.
  # Best-effort: only what WhatsApp synced to the device is available.
  def run
    imported = import_messages
    finalize_conversation if imported.positive?
    enqueue_media
    imported
  end

  private

  # Cursor-based pagination by (timestamp, external id) — not offset, which GOWS
  # doesn't reliably honor, and not timestamp alone, which loses messages once
  # more than a page's worth share one second (GOWS' only sort/filter field is
  # second-resolution timestamp, with no documented tie-break). Every fetched
  # page is re-sorted client-side by that composite key — we never trust the
  # engine's own ordering — and only items strictly after the last confirmed
  # pair are written, so the inclusive `gte` filter re-fetching confirmed rows
  # can never duplicate or stall them. Progress persists per page for resume.
  def import_messages
    imported = 0
    @media_message_ids = Set.new(import_chat.media_message_ids)
    cursor = resume_cursor
    loop do
      raw_page = fetch_page(cursor[:ts])
      break if raw_page.blank?

      delta, next_cursor, full_page = handle_page(raw_page, cursor)
      imported += delta
      break if next_cursor.nil?

      cursor = next_cursor
      break unless full_page
    end
    imported
  end

  # Resolves one fetched page end-to-end: widens an ambiguous same-second page,
  # resolves (once) the conversation it belongs to, keeps only items strictly
  # after the confirmed cursor, and persists progress. Returns [imported_delta,
  # next_cursor, full_page]; a nil next_cursor tells the caller to stop —
  # either the chat has no conversation to resolve into, or #next_cursor_for
  # found the legitimate end of the window (see it for the stall distinction).
  def handle_page(raw_page, cursor)
    ordered, resolved_tie = resolve_page(raw_page)
    full_page = raw_page.size == PAGE_SIZE
    @conversation ||= resolve_conversation(ordered)
    return [0, nil, full_page] unless @conversation

    @existing_messages ||= load_existing_messages
    new_items = ordered.select { |payload| after_cursor?(payload, cursor) }
    next_cursor = next_cursor_for(new_items, cursor, resolved_tie: resolved_tie, full_page: full_page)
    return [0, nil, full_page] if next_cursor.nil?

    [write_page(new_items, next_cursor), next_cursor, full_page]
  end

  # Widens an ambiguous same-second page (see #tied_second?) into the full
  # cluster and returns it client-sorted by the composite key, alongside
  # whether that widen conclusively resolved the whole cluster (short of the
  # cap) — the one case where "no new items" below legitimately means
  # "already fully confirmed" rather than a stalled page.
  def resolve_page(raw_page)
    tied = tied_second?(raw_page)
    page = tied ? fetch_tied_second(raw_page.first['timestamp'].to_i) : raw_page
    [sort_by_composite_key(page), tied && page.size < MAX_TIED_SECOND_SIZE]
  end

  # A full-size page that sits entirely within one second can't be trusted to
  # be the whole cluster — it may just be the first PAGE_SIZE of a larger one.
  # Computed from the payload timestamps, not the page's return order: GOWS'
  # ordering stability across ties isn't guaranteed, so this must not assume
  # the page arrived pre-sorted.
  def tied_second?(page)
    return false if page.size < PAGE_SIZE

    timestamps = page.map { |payload| payload['timestamp'].to_i }
    timestamps.min == timestamps.max
  end

  # Resolves an ambiguous same-second page in one shot: re-fetch that exact
  # second alone with a much larger limit. A result short of the cap proves
  # it's the complete cluster; the loop treats a cluster that still hits the
  # cap as a stall (see #next_cursor_for) rather than growing the request
  # without bound.
  def fetch_tied_second(second)
    fetch_page(second, limit: MAX_TIED_SECOND_SIZE, upper: second)
  end

  # The composite cursor to persist for this page, or nil to end the run
  # cleanly. A same-second cluster that #resolve_page conclusively widened
  # is allowed to advance past its own second even with nothing new to
  # write; a short (non-full) page with nothing new is simply the end of
  # the window; only a full page that still makes zero progress is a real
  # stall — an observable failure, never a loop or a false completion.
  def next_cursor_for(new_items, cursor, resolved_tie:, full_page:)
    return composite_key(new_items.last) if new_items.present?
    return { ts: cursor[:ts] + 1, id: nil } if resolved_tie
    return nil unless full_page

    # A full page that advanced the cursor by nothing: the engine is returning
    # the same window forever. Distinct from a failed fetch and from a finished
    # chat, and reported as such before the exception stops the chat.
    Waha::Telemetry.emit(
      :import_stalled, channel: channel, chat: chat_id, level: :error, kind: kind,
                       reason: :no_progress, cursor_ts: cursor[:ts], page_size: PAGE_SIZE
    )
    raise CustomExceptions::Waha::ApiError, stall_message(cursor)
  end

  # Resume from the row's persisted composite cursor after a restart; otherwise
  # start at the window's lower bound with nothing yet confirmed.
  def resume_cursor
    { ts: import_chat.cursor || window_unix('window_start'), id: import_chat.cursor_message_id }
  end

  # An item counts as new only if it's strictly after the last confirmed
  # (timestamp, external id) pair — never solely because it satisfies the
  # engine's inclusive per-second `gte` filter, which re-returns confirmed rows.
  def after_cursor?(payload, cursor)
    ts = payload['timestamp'].to_i
    return ts > cursor[:ts] unless ts == cursor[:ts]

    cursor[:id].nil? || external_id(payload) > cursor[:id]
  end

  def sort_by_composite_key(page)
    page.sort_by { |payload| [payload['timestamp'].to_i, external_id(payload)] }
  end

  def composite_key(payload)
    { ts: payload['timestamp'].to_i, id: external_id(payload) }
  end

  # The stable tie-break: WAHA's own message identity (see Waha::Anchoring),
  # not a chronological guarantee — same convention the rest of the importer
  # already uses to key on a message. Falls back to '' for an unparseable id
  # so a malformed payload still gets an orderable (if not unique) position.
  def external_id(payload)
    Waha::Anchoring.stanza_of(payload['id']).presence || ''
  end

  def stall_message(cursor)
    "WAHA history import stalled for chat #{chat_id} at timestamp #{cursor[:ts]}: a full page made no progress"
  end

  # Per-page progress on the chat's own row (single-row write, no jsonb churn):
  # bumps its imported count and persists the composite cursor for mid-chat resume.
  def write_page(new_items, next_cursor)
    imported = new_items.count { |payload| write_message(payload) }
    import_chat.update!(cursor: next_cursor[:ts], cursor_message_id: next_cursor[:id],
                        media_message_ids: @media_message_ids.to_a, imported_count: import_chat.imported_count + imported)
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

    message = Waha::HistoryMessageWriter.new(
      channel: channel, payload: payload, conversation: @conversation, kind: kind
    ).perform

    return false unless message

    @existing_messages[stanza] = message.id
    track_media(message.id, payload)

    if message.previously_new_record?
      track_timestamp(payload['timestamp'].to_i)
      true
    else
      false
    end
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
      account_id: inbox.account_id, inbox_id: inbox.id,
      contact_id: contact_inbox.contact_id, contact_inbox_id: contact_inbox.id
    )
    conversation.imported = initial_import?
    conversation.save!
    conversation
  end

  def load_existing_messages
    candidate_chat_jids = Waha::Anchoring.chat_jids(channel, [@conversation.contact_inbox&.source_id, chat_id])

    rows = channel.message_mappings.resolved.where(chat_jid: candidate_chat_jids, event_type: :message).pluck(:external_id, :message_id)
    rows.group_by(&:first).transform_values do |parts|
      ids = parts.map(&:last).uniq
      raise CustomExceptions::Waha::AmbiguousIdentity, "channel=#{channel.id} history identity matches multiple messages" if ids.many?

      ids.first
    end
  end

  def track_timestamp(unix)
    return if unix.zero?

    @min_ts = unix if @min_ts.nil? || unix < @min_ts
    @max_ts = unix if @max_ts.nil? || unix > @max_ts
  end

  # Initial imports land resolved and read (no unread badges), with their
  # activity/creation timestamps extended to span the imported history. A recent
  # gap-fill has already run the normal message path, so it deliberately leaves
  # the conversation status and seen timestamps alone.
  def finalize_conversation
    return unless initial_import?

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

  def fetch_page(cursor_ts, limit: PAGE_SIZE, upper: window_unix('window_end'))
    query = {
      'limit' => limit,
      'sortBy' => 'timestamp', 'sortOrder' => 'asc', 'downloadMedia' => false,
      'filter.timestamp.gte' => cursor_ts,
      'filter.timestamp.lte' => upper
    }.to_query

    http_client.get_array("#{channel.session_name}/chats/#{chat_id}/messages?#{query}")
  end

  def window_unix(key)
    Time.zone.parse(window[key]).to_i
  end

  def initial_import?
    kind == 'initial'
  end

  def inbox
    @inbox ||= channel.inbox
  end

  def http_client
    @http_client ||= Waha::HttpClient.new(channel: channel)
  end
end
# rubocop:enable Metrics/ClassLength
