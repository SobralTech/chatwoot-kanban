# The edit-family invariant, in one place.
#
# WhatsApp keeps a single message across N edits, while Chatwoot mirrors each
# edit as a fresh message anchored to the original's source_id via
# additional_attributes['edit_of']. Replies, reactions, deletes and edits all
# depend on resolving that anchor the same way, so every consumer reads it here.
module Waha::Anchoring
  module_function

  # edit_of points at the original message's source_id for every edit mirror;
  # a message that was never edited is its own anchor.
  def anchor_source_id(message)
    message.additional_attributes['edit_of'].presence || message.source_id
  end

  # The anchor (the single real WhatsApp message) plus every edit mirror
  # pointing at it.
  def family(inbox, anchor_source_id)
    messages = inbox.messages
    messages.where(source_id: anchor_source_id)
            .or(messages.where("additional_attributes->>'edit_of' = ?", anchor_source_id))
  end

  # WAHA source_ids are `direction_chat_stanza`; the trailing stanza is the
  # message identity and the only part stable across engines and directions.
  def stanza_of(source_id)
    source_id.to_s.split('_').last
  end

  # Every message matching a source_id's stanza, as a relation so callers can
  # pick the shape they need (exists?, first, conversation-scoped).
  def by_stanza(inbox, source_id)
    stanza = stanza_of(source_id)
    return inbox.messages.none if stanza.blank?

    inbox.messages.where('source_id LIKE ?', "%_#{stanza}")
  end
end
