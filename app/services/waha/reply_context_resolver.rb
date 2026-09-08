class Waha::ReplyContextResolver
  PREVIEW_LENGTH = 140
  # Waha::MediaAttacher's engine-aware kinds, mapped onto the attachment file
  # types the ghost quote labels ("Photo", "Audio", ...).
  QUOTED_MEDIA_TYPES = { 'image' => 'image', 'sticker' => 'image', 'audio' => 'audio', 'video' => 'video', 'document' => 'file' }.freeze

  pattr_initialize [:channel!, :payload!, :conversation!]

  # WhatsApp keeps a single message across N edits; every edit mirror anchors to
  # the original through its mapping, so the head (latest version) is what the contact
  # actually saw when replying.
  def self.family_head(inbox, original)
    Waha::Anchoring.family(inbox, original)
                   .order(:created_at)
                   .last || original
  end

  # Resolves a payload's replyTo into content_attributes for the new message:
  # - quoted message in this conversation  -> in_reply_to (local id, clickable quote)
  # - quoted message in another conversation, or unknown (pre-inbox/status)
  #   -> in_reply_to_snapshot (render-ready ghost quote, not clickable)
  # in_reply_to_external_id always carries the family anchor source_id when
  # resolved, or the raw stanza when not.
  def perform
    return {} if stanza.blank?

    original ? resolve_local : payload_snapshot
  end

  private

  def stanza
    # replyTo.id carries only the stanza (e.g. 3EB061968E662308B1CAEE), but we
    # normalize just like the dedupe path in case a full source_id shows up.
    @stanza ||= Waha::Anchoring.stanza_of(payload.dig('replyTo', 'id'))
  end

  def original
    return @original if defined?(@original)

    quoted_id = payload.dig('replyTo', 'id')
    chat_jid = Waha::Anchoring.chat_jid_of(quoted_id) || conversation.contact_inbox.source_id
    @original = Waha::Anchoring.find_message(channel, quoted_id, chat_jid)
  end

  def head
    @head ||= self.class.family_head(inbox, original)
  end

  def resolve_local
    if head.conversation_id == conversation.id
      { in_reply_to: head.id, in_reply_to_external_id: Waha::Anchoring.external_anchor_source_id(original) }
    else
      # Inbox in "create new conversations" mode: the frontend can't render or
      # scroll to a message from another conversation, so feed a ghost quote
      # with the real local content instead.
      { in_reply_to_external_id: Waha::Anchoring.external_anchor_source_id(original), in_reply_to_snapshot: snapshot_of(head) }
    end
  end

  def payload_snapshot
    # Quoted message predates the inbox (or is a status): snapshot whatever the
    # payload carries. Replies marked on the WhatsApp app bring body/participant;
    # API-sent echoes bring only the id, leaving an empty snapshot the frontend
    # renders as "message not available".
    {
      in_reply_to_external_id: stanza,
      in_reply_to_snapshot: {
        body: payload.dig('replyTo', 'body'),
        author: snapshot_author,
        media_type: quoted_media_type
      }.compact
    }
  end

  # A status reply quotes a story this inbox never imports, so the ghost quote
  # is the only place the agent sees it: label it so the quote is not mistaken
  # for an ordinary earlier message from the same person.
  def snapshot_author
    author = resolve_participant(payload.dig('replyTo', 'participant'))
    return author unless Waha::StatusContext.reply_to_status?(payload)
    return I18n.t('conversations.messages.waha_status_reply.quoted_author_unknown') if author.blank?

    I18n.t('conversations.messages.waha_status_reply.quoted_author', author: author)
  end

  # GOWS puts the quoted message's own proto under `replyTo._data`, so quoted
  # media can be labelled precisely instead of as a generic file.
  def quoted_media_type
    return nil unless payload.dig('replyTo', 'hasMedia')

    quoted = payload.dig('replyTo', '_data')
    quoted = {} unless quoted.is_a?(Hash)
    kind = Waha::MediaAttacher::DATA_MESSAGE_KINDS.find { |key, _| quoted[key].present? }&.last
    QUOTED_MEDIA_TYPES.fetch(kind, 'file')
  end

  def snapshot_of(message)
    {
      body: message.content&.truncate(PREVIEW_LENGTH),
      author: author_of(message),
      media_type: message.attachments.first&.file_type
    }.compact
  end

  def author_of(message)
    message.content_attributes['sender_name'].presence ||
      message.sender&.name.presence ||
      message.additional_attributes['sender_name'].presence
  end

  def resolve_participant(jid)
    return if jid.blank?

    name = Waha::ParticipantResolver.new(channel: channel, jid: jid).perform.name
    return name if name.present?

    Waha::Jid.lid?(jid) ? jid : "+#{Waha::Jid.digits(jid)}"
  end

  def inbox
    @inbox ||= channel.inbox
  end
end
