class Waha::ReplyContextResolver
  PREVIEW_LENGTH = 140

  pattr_initialize [:channel!, :payload!, :conversation!]

  # WhatsApp keeps a single message across N edits; every edit mirror anchors to
  # the original via edit_of, so the head (latest version) is what the contact
  # actually saw when replying.
  def self.family_head(inbox, original)
    inbox.messages
         .where("additional_attributes->>'edit_of' = ?", original.source_id)
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
    @stanza ||= payload.dig('replyTo', 'id').to_s.split('_').last
  end

  def original
    return @original if defined?(@original)

    # Prefer a match in the current conversation: stanzas are only guaranteed
    # unique per chat, so this minimizes cross-chat false positives.
    scope = inbox.messages.where('source_id LIKE ?', "%_#{stanza}")
    @original = scope.find_by(conversation_id: conversation.id) || scope.first
  end

  def head
    @head ||= self.class.family_head(inbox, original)
  end

  def resolve_local
    if head.conversation_id == conversation.id
      { in_reply_to: head.id, in_reply_to_external_id: original.source_id }
    else
      # Inbox in "create new conversations" mode: the frontend can't render or
      # scroll to a message from another conversation, so feed a ghost quote
      # with the real local content instead.
      { in_reply_to_external_id: original.source_id, in_reply_to_snapshot: snapshot_of(head) }
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
        author: resolve_participant(payload.dig('replyTo', 'participant')),
        media_type: ('file' if payload.dig('replyTo', 'hasMedia'))
      }.compact
    }
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

    contact = find_contact(jid)
    return contact.name if contact&.name.present?

    digits = jid.to_s.split('@').first.to_s.split(':').first
    jid.to_s.end_with?('@lid') ? jid : "+#{digits}"
  end

  def find_contact(jid)
    if jid.to_s.end_with?('@lid')
      channel.account.contacts.where("additional_attributes->>'lid' = ?", jid).first
    else
      digits = jid.to_s.split('@').first.to_s.split(':').first
      channel.account.contacts.find_by(phone_number: "+#{digits}")
    end
  end

  def inbox
    @inbox ||= channel.inbox
  end
end
