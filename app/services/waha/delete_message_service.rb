class Waha::DeleteMessageService < Waha::BaseMessageActionService
  pattr_initialize [:message!]

  # Revokes a message on WhatsApp ("delete for everyone"). WhatsApp keeps a
  # single message across N edits, so we always target the family anchor (the
  # original message's source_id), even when the agent deletes a later edit
  # mirror. The returning message.revoked webhook soft-deletes the whole family.
  def perform
    dispatch!(:delete, message_path)
  end
end
