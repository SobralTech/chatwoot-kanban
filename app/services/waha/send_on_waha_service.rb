# rubocop:disable Metrics/ClassLength
class Waha::SendOnWahaService < Base::SendOnChannelService
  TYPING_PRESENCE_QUEUE_WAIT_LIMIT = 20_000

  # Retries apply only to CustomExceptions::Waha::TransientError (5xx, timeout,
  # connection failure). MAX_SEND_ATTEMPTS counts the original try, so this
  # allows 2 retries before the message is marked failed for good. Counted off
  # WahaDeliveryAttempt#attempt_count (persisted), not a job argument, so it
  # survives a crash between send and confirmation.
  MAX_SEND_ATTEMPTS = 3
  RETRY_DELAYS = [10.seconds, 60.seconds].freeze

  # How far back to look, in a chat's own message list, for a message carrying
  # our pre-generated id when a send's outcome is unknown (see
  # #reconcile_ambiguous_dispatch!).
  RECONCILIATION_LOOKBACK = 20

  pattr_initialize [:message!, :skip_presence]

  private

  def channel_class
    Channel::Waha
  end

  # A partially delivered multipart message already has the first part's
  # source_id as its stable anchor. Unlike a channel-originated mirror, it must
  # keep passing the base service guard until its aggregate attempt is sent.
  def outgoing_message_originated_from_channel?
    attempt = message.waha_delivery_attempt
    message.waha_message_mappings.exists? && (attempt.nil? || attempt.sent?)
  end

  def perform_reply
    send_seen

    if skip_presence
      pause_presence
      deliver_message
    elsif clock_enabled?
      reserve_and_queue_delivery
    else
      deliver_message
    end
  rescue CustomExceptions::Waha::TransientError => e
    handle_transient_failure(e)
  rescue StandardError => e
    fail_message!(e)
  end

  # Claims the persisted attempt (a no-op if another execution is already
  # sending), assigns a WAHA-generated id up front when the engine supports it,
  # and confirms the send atomically once WAHA responds with a message id.
  def deliver_message
    return unless delivery_attempt.claim!

    ensure_delivery_parts!
    return release_attempt!(:no_deliverable_parts) if delivery_parts.empty?

    delivery_parts.pending.in_delivery_order.each do |part|
      return nil unless dispatch_part!(part)
    end
  end

  # Sends one part and turns WAHA's response into that part's checkpoint.
  # Returns false when the part had nothing to send, which releases the attempt
  # rather than leaving it claimed.
  def dispatch_part!(part)
    ensure_client_message_id!(part)
    dispatched_at = Time.current
    part.update!(dispatched_at: dispatched_at)
    delivery_attempt.update!(dispatched_at: dispatched_at)
    emit(:delivery_dispatched, part: part, part_type: part.part_type)

    result = deliver_part(part)
    if result.nil?
      release_attempt!(:unresolved_attachment, part)
      return false
    end

    wa_message_id = result.is_a?(Hash) ? result['id'] : nil
    raise CustomExceptions::Waha::ApiError, 'WAHA accepted the request but returned no message id' if wa_message_id.blank?

    confirm_part!(part, wa_message_id)
    true
  end

  # The pre-generated id the request carried is replaced here by the id WhatsApp
  # assigned, so this is where an outgoing trace joins the `waha_id` every
  # inbound signal for the same message uses — whether the confirmation came
  # from the response or from reconciling an ambiguous dispatch.
  def confirm_part!(part, wa_message_id)
    delivery_attempt.confirm_part_sent!(part, wa_message_id)
    emit(:delivery_confirmed, level: :info, part: part, part_type: part.part_type,
                              waha_id: Waha::Anchoring.stanza_of(wa_message_id).presence)
  end

  # WAHA's pre-generated id is the closest thing GOWS offers to a client-defined
  # idempotency key (see MessageTextRequest#id upstream): reused across retries
  # of the same message, it lets a correlated fromMe echo or a reconciliation
  # scan confirm a send whose HTTP response never came back. Some engines don't
  # support the endpoint; that's a documented, observable limitation, not a
  # reason to fail the send.
  def ensure_client_message_id!(part)
    return if part.client_message_id.present?

    id = fetch_client_message_id
    return if id.blank?

    part.update!(client_message_id: id)
  end

  def fetch_client_message_id
    http_client.get("#{channel.session_name}/new-message-id")['id']
  rescue CustomExceptions::Waha::TransientError
    raise
  rescue CustomExceptions::Waha::ApiError => e
    # Without a client-defined id every send on this engine is potentially
    # ambiguous after a lost response, so the limitation is a standing signal
    # rather than an incident.
    emit(:delivery_without_idempotency_key, level: :warn, reason: :engine_unsupported, error: e.class.name)
    nil
  end

  # An attachment we can't resolve a URL for leaves nothing to retry towards, so
  # release the claim instead of leaving the attempt stuck in `sending` forever.
  def release_attempt!(reason = nil, part = nil)
    delivery_attempt.update!(status: :pending)
    emit(:delivery_released, level: :warn, reason: reason, part: part, part_type: part&.part_type) if reason
    nil
  end

  def handle_transient_failure(error)
    if reconcile_ambiguous_dispatch!
      return if delivery_attempt.sent?

      return resume_delivery!
    end

    if delivery_attempt.attempt_count < MAX_SEND_ATTEMPTS
      return unless delivery_attempt.release_to_pending!(error.message)

      delay = RETRY_DELAYS[delivery_attempt.attempt_count - 1]
      emit(:delivery_retry_scheduled, level: :warn, error: error.class.name, delay_ms: delay.in_milliseconds)
      Waha::DeliverJob.set(wait: delay).perform_later(message.id)
    else
      fail_message!(error)
    end
  end

  # The request that carried our pre-generated id may have reached WAHA despite
  # the local error (timeout, reset, 5xx). Before assuming nothing happened and
  # resending, check whether that id already shows up as a message WAHA sent.
  # Only meaningful once a request was actually dispatched with a known id; a
  # failure before that point (e.g. fetching the id itself) has nothing to
  # reconcile against.
  def reconcile_ambiguous_dispatch!
    part = delivery_parts.pending.where('dispatched_at IS NOT NULL AND client_message_id IS NOT NULL').in_delivery_order.first
    return false unless part

    match = recent_own_messages.find { |msg| Waha::Anchoring.stanza_of(msg['id']) == part.client_message_id }
    # A request left this process with an outcome we do not know: whether the
    # reconciliation scan then found it on WhatsApp or not, the ambiguity itself
    # is the signal, and `outcome` says how it was settled.
    emit(:delivery_ambiguous, level: :warn, part: part, part_type: part.part_type,
                              outcome: match ? :recovered : :unresolved)
    return false unless match

    confirm_part!(part, match['id'])
    true
  rescue StandardError => e
    emit(:delivery_ambiguous, level: :warn, outcome: :check_failed, error: e.class.name)
    false
  end

  def recent_own_messages
    query = "limit=#{RECONCILIATION_LOOKBACK}&filter.fromMe=true&sortOrder=desc&downloadMedia=false"
    http_client.get_array("#{channel.session_name}/chats/#{chat_id}/messages?#{query}")
  end

  def resume_delivery!
    return unless delivery_attempt.release_to_pending!

    Waha::DeliverJob.perform_later(message.id)
  end

  def fail_message!(error)
    return unless delivery_attempt.mark_failed!(error.message)

    emit(:delivery_failed, level: :error, error: error.class.name, confirmed_parts: delivery_parts.sent.count,
                           total_parts: delivery_parts.count)
    message.update!(status: :failed, external_error: error.message)
  end

  # The correlation every outgoing signal shares. `attempt_id` and `try` pin a
  # line to one persisted send attempt, so a late signal from a superseded
  # attempt is never mistaken for the current one; the error text itself stays
  # on the attempt row and the message, and never enters a signal.
  def emit(signal, level: :debug, part: nil, **context)
    Waha::Telemetry.emit(
      signal, channel: channel, chat: chat_id, level: level, direction: :outgoing,
              message_id: message.id, conversation_id: conversation.id, attempt_id: delivery_attempt.id,
              try: delivery_attempt.attempt_count, part: part&.position, **context
    )
  end

  def delivery_attempt
    @delivery_attempt ||= WahaDeliveryAttempt.create_or_find_by!(message: message) do |a|
      a.channel = channel
      a.chat_jid = chat_id
    end
  end

  def reserve_and_queue_delivery
    humanized = humanization_enabled?
    duration_ms = humanized ? typing_duration_ms : 0
    queue_wait_ms, total_wait_ms = conversation_clock.reserve(duration_ms)
    if humanized && queue_wait_ms <= TYPING_PRESENCE_QUEUE_WAIT_LIMIT
      presence_client.public_send(audio_message? ? :recording : :typing, chat_id)
    end
    Waha::DeliverJob.set(wait: total_wait_ms / 1000.0).perform_later(message.id)
  rescue Redis::BaseError, ConnectionPool::TimeoutError => e
    warn_clock_unavailable(e)
    deliver_message
  end

  def typing_duration_ms
    (Waha::TypingSimulator.duration_for(message.content) * 1000).round
  end

  def pause_presence
    return unless clock_enabled?
    return if conversation_clock.backlog?

    presence_client.paused(chat_id)
  rescue Redis::BaseError, ConnectionPool::TimeoutError => e
    warn_clock_unavailable(e)
  end

  def warn_clock_unavailable(error)
    emit(:delivery_clock_unavailable, level: :warn, error: error.class.name)
  end

  def send_seen
    return if skip_presence || !channel.auto_read_receipts || presence_excluded?

    incoming = conversation.last_incoming_message
    source_id = Waha::Anchoring.external_anchor_source_id(incoming) if incoming
    return if source_id.blank?

    presence_client.seen(chat_id, message_ids: [source_id])
  end

  def clock_enabled?
    channel.typing_simulation_enabled? && !presence_excluded?
  end

  def humanization_enabled?
    return false unless clock_enabled?

    text_message? || audio_message?
  end

  def presence_excluded?
    message.additional_attributes['campaign_id'].present? || Waha::Jid.group?(chat_id)
  end

  def text_message?
    eligible_attachments.empty? && outgoing_mentions.text.present?
  end

  def audio_message?
    eligible_attachments.one? && eligible_attachments.first.file_type.to_s == 'audio'
  end

  def delivery_parts
    delivery_attempt.delivery_parts
  end

  def ensure_delivery_parts!
    delivery_attempt.with_lock do
      next if delivery_parts.exists?

      position = 0
      if outgoing_mentions.text.present? && eligible_attachments.size != 1
        delivery_parts.create!(position: position, part_type: :text)
        position += 1
      end
      eligible_attachments.each do |attachment|
        delivery_parts.create!(position: position, part_type: :attachment, attachment: attachment)
        position += 1
      end
    end
  end

  def eligible_attachments
    @eligible_attachments ||= message.attachments.to_a.select { |item| item.file.attached? }.sort_by(&:id)
  end

  def deliver_part(part)
    part.text? ? send_text(part) : send_attachment(part)
  end

  def conversation_clock
    @conversation_clock ||= Waha::ConversationClock.new(conversation_id: conversation.id)
  end

  def presence_client
    @presence_client ||= Waha::PresenceClient.new(channel: channel)
  end

  def send_text(part)
    http_client.post('sendText', base_payload(part).merge(outgoing_mentions.payload, text: signer.sign(outgoing_mentions.text)))
  end

  def send_attachment(part)
    attachment = eligible_attachments.find { |item| item.id == part.attachment_id }
    return if attachment.nil?

    file_url = attachment_url(attachment)
    return if file_url.blank?

    endpoint, body = attachment_endpoint_and_body(attachment.file_type.to_sym, attachment, file_url, attachment_caption)
    http_client.post(endpoint, base_payload(part).merge(body))
  end

  def blob(attachment)
    attachment.file.blob
  end

  # WAHA's RemoteFile requires mimetype; sendFile also needs filename to preserve
  # the document name on WhatsApp. Passing them explicitly avoids the "422 file
  # invalid" the server returns for a bare `{ url: ... }`.
  def attachment_endpoint_and_body(file_type, attachment, file_url, caption_text)
    caption = signer.sign(caption_text)
    remote_file = remote_file_for(attachment, file_url)
    caption_payload = media_payload(remote_file, caption)
    case file_type
    when :image  then ['sendImage', caption_payload]
    when :audio  then ['sendVoice', { file: remote_file }]
    when :video  then ['sendVideo', caption_payload]
    else              ['sendFile', caption_payload]
    end
  end

  def remote_file_for(attachment, file_url)
    { url: file_url, mimetype: blob(attachment)&.content_type.presence,
      filename: blob(attachment)&.filename&.to_s.presence }.compact
  end

  def media_payload(remote_file, caption)
    payload = { file: remote_file, caption: caption }.compact
    caption.present? ? payload.merge(outgoing_mentions.payload) : payload
  end

  def attachment_caption
    outgoing_mentions.text.presence if eligible_attachments.one?
  end

  def base_payload(part)
    payload = {
      session: channel.session_name,
      chatId: chat_id
    }

    # The WAHA send API takes reply_to (snake_case); replyTo only appears in
    # incoming webhook payloads.
    reply_to_id = quoted_source_id
    payload[:reply_to] = reply_to_id if reply_to_id.present?
    payload[:id] = part.client_message_id if part.client_message_id.present?

    payload
  end

  # `outgoing_content` (not the raw `content`) so an input_csat message picks up
  # the survey link the same way every other non-web-widget channel's send
  # service already does — see MessageContentPresenter#outgoing_content.
  def outgoing_mentions
    @outgoing_mentions ||= Waha::OutgoingMentionParser.new(text: message.outgoing_content, chat_id: chat_id)
  end

  def chat_id
    contact_inbox.source_id
  end

  # WhatsApp keeps a single message across N edits, so when the agent replies to
  # an edit mirror the replyTo must be the family anchor (the original message's
  # source_id) — otherwise WhatsApp won't find the quoted message.
  def quoted_source_id
    external_id = message.content_attributes&.dig('in_reply_to_external_id')
    in_reply_to_id = message.content_attributes&.dig('in_reply_to')

    quoted = quoted_message(external_id, in_reply_to_id)
    return external_id if quoted.blank?

    Waha::Anchoring.external_anchor_source_id(quoted)
  end

  def quoted_message(external_id, in_reply_to_id)
    (Waha::Anchoring.find_message(channel, external_id, chat_id) if external_id.present?) ||
      (inbox.messages.find_by(id: in_reply_to_id) if in_reply_to_id.present?)
  end

  def attachment_url(attachment)
    return unless attachment.file.attached?

    # `download_url` returns the pre-signed blob URL directly, without the 301
    # redirect that WAHA's downloader doesn't follow.
    attachment.download_url.presence
  rescue StandardError
    nil
  end

  def http_client
    @http_client ||= Waha::HttpClient.new(channel: channel)
  end

  def signer
    @signer ||= Waha::MessageSigner.new(message: message)
  end
end
# rubocop:enable Metrics/ClassLength
