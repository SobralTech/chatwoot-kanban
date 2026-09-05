# A reply to a WhatsApp status (story). The reply lands in the normal direct
# chat and carries its own text or media, so this wraps whichever converter the
# registry picked for that content and only adds the explicit marker — the
# policy is a recorded decision, not the side effect of a generic filter.
#
# The quoted story itself is recovered by Waha::ReplyContextResolver, which
# renders it as a ghost quote labelled as a status; status chats are never
# imported, so the quoted message never exists locally.
class Waha::MessageConverters::StatusReply < Waha::MessageConverters::Base
  pattr_initialize [:inner!]

  def download
    inner.download
  end

  def content
    inner.content
  end

  def metadata
    inner.metadata.merge(is_status_reply: true)
  end

  def attach(message)
    inner.attach(message)
  end

  def downloads_attachment?
    inner.downloads_attachment?
  end
end
