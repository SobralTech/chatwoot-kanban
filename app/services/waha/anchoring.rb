# The edit-family invariant, in one place.
#
# WhatsApp keeps a single message across N edits, while Chatwoot mirrors each
# edit as a fresh message anchored to the original's source_id via
# additional_attributes['edit_of']. Replies, reactions, deletes and edits all
# depend on resolving that anchor the same way, so every consumer reads it here.
module Waha::Anchoring
  # The same trailing-stanza extraction as `stanza_of`, expressed in SQL. Kept
  # byte-identical to the expression behind index_messages_on_inbox_and_source_stanza
  # so the planner can use it.
  #
  # A group message id carries a trailing `_<participantJid>` segment
  # (`direction_chat_stanza_participant`) that a plain "after the last
  # underscore" split would return instead of the real stanza — and since a
  # participant sends many messages, that collided every one of their
  # messages after the first onto a single false "duplicate". Strip that
  # trailing `_...@...` segment (chat/participant JIDs are the only parts
  # containing "@") before taking what's after the last remaining underscore.
  STANZA_SQL = "regexp_replace(regexp_replace(source_id, '_[^_]*@[^_]*$', ''), '^.*_', '')".freeze

  module_function

  # edit_of points at the original message's source_id for every edit mirror;
  # a message that was never edited is its own anchor.
  def anchor_source_id(message)
    message.additional_attributes['edit_of'].presence || message.source_id
  end

  # Multipart messages use their first part as the stable default target for
  # replies, edits and reactions. Legacy rows keep using Message#source_id.
  def external_anchor_source_id(message)
    anchor = family_anchor_message(message)

    anchor.waha_delivery_attempt&.delivery_parts&.sent&.in_delivery_order&.pick(:source_id).presence || anchor.source_id
  end

  def family_anchor_message(message)
    edit_of = message.additional_attributes['edit_of']
    return message if edit_of.blank?

    message.inbox.messages.find_by(source_id: edit_of) || message
  end

  # The anchor (the single real WhatsApp message) plus every edit mirror
  # pointing at it.
  def family(inbox, anchor_source_id)
    messages = inbox.messages
    messages.where(source_id: anchor_source_id)
            .or(messages.where("additional_attributes->>'edit_of' = ?", anchor_source_id))
  end

  # WAHA source_ids are `direction_chat_stanza`, or `direction_chat_stanza_participant`
  # for a group message; the stanza is the message identity and the only part
  # stable across engines and directions. Drop the JID-shaped segments (they're
  # the only ones containing "@") and take what's left — see STANZA_SQL.
  def stanza_of(source_id)
    source_id.to_s.split('_').reject { |part| part.include?('@') }.last
  end

  # Full WAHA ids start with direction_chatJid_...; group ids can also end in a
  # participant JID, so the first JID-shaped segment is always the chat.
  def chat_jid_of(source_id)
    source_id.to_s.split('_').find { |part| part.include?('@') }
  end

  # The one way to go from a WAHA message id back to the Chatwoot message it
  # mirrors. The canonical mapping is the primary correlation (it also covers
  # the non-anchor parts of a multipart send); the stanza scan is the fallback
  # for rows written before the mapping existed. Both are scoped by chat so a
  # stanza that repeats across chats can never resolve to the wrong conversation.
  def find_message(channel, source_id, chat_jid = nil)
    chat_jid ||= chat_jid_of(source_id)
    mapping = WahaMessageMapping.find_mapping(channel: channel, chat_jid: chat_jid, external_id: stanza_of(source_id))
    return mapping.message if mapping

    messages = by_stanza(channel.inbox, source_id)
    messages = messages.where("split_part(source_id, '_', 2) = ?", chat_jid) if chat_jid
    messages.first
  end

  # Every message matching a source_id's stanza, as a relation so callers can
  # pick the shape they need (exists?, first, conversation-scoped).
  def by_stanza(inbox, source_id)
    stanza = stanza_of(source_id)
    return inbox.messages.none if stanza.blank?

    inbox.messages.where("#{STANZA_SQL} = ?", stanza)
  end
end
