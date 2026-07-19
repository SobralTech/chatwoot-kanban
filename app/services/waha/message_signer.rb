class Waha::MessageSigner
  pattr_initialize [:message!]

  # WhatsApp renders *_..._* as bold-italic, so agent replies arrive prefixed
  # with the sender's name on their own line.
  SIGNATURE_TEMPLATE = "*_%<name>s_*:\n%<content>s".freeze

  # Prefixes text with the agent's signature when the inbox has signing enabled
  # and the message is an outgoing reply from a human agent. Blank text (e.g. an
  # attachment with no caption) is left untouched so we never invent a caption.
  def sign(text)
    return text if text.blank?
    return text unless signable?

    format(SIGNATURE_TEMPLATE, name: sender.available_name, content: text)
  end

  private

  def signable?
    channel.signing_enabled? && message.outgoing? && sender.is_a?(User)
  end

  def channel
    message.inbox.channel
  end

  def sender
    message.sender
  end
end
