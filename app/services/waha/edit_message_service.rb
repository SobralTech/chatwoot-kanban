class Waha::EditMessageService < Waha::BaseMessageActionService
  pattr_initialize [:message!, :content!]

  # Pushes an edit to WhatsApp. WhatsApp keeps a single message across N edits,
  # so we always target the family anchor (the original message's source_id),
  # even when the agent edits a later mirror. The returning message.edited
  # webhook drives the local strike-through + new message.
  def perform
    # Attributes the mirror to the agent who clicked edit instead of the generic
    # "sent from WhatsApp" label.
    stash_current_user('pending_edited_by_id')
    dispatch!(:put, message_path, { text: Waha::MessageSigner.new(message: message).sign(content) })
  end
end
