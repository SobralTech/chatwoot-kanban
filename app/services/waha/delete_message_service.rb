class Waha::DeleteMessageService < Waha::BaseMessageActionService
  pattr_initialize [:message!]

  # Revokes every external part produced by this Chatwoot message. For a legacy
  # or single-part message this remains one request; an edit mirror resolves to
  # the original multipart attempt. The returning message.revoked webhook
  # soft-deletes the whole local family idempotently.
  def perform
    message_paths.each { |path| dispatch!(:delete, path) }
  end
end
