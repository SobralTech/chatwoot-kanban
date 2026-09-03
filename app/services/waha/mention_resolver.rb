class Waha::MentionResolver
  pattr_initialize [:channel!, :payload!]

  # WhatsApp mentions arrive as a raw "@<lid or phone digits>" token in the body
  # text, resolvable via the message's own mentionedJID list. Resolves each to a
  # Chatwoot contact (creating it if new, same as any other WAHA contact) and
  # swaps in its name.
  def resolve(body)
    return body if body.blank?

    mentioned_jids.reduce(body) do |text, jid|
      contact = Waha::ContactResolver.new(channel: channel, jid: jid).perform&.contact
      next text unless contact

      text.gsub("@#{Waha::Jid.digits(jid)}", "@#{contact.name}")
    end
  end

  private

  def mentioned_jids
    message_node = payload.dig('_data', 'Message')
    return [] unless message_node.is_a?(Hash)

    message_node.values.filter_map { |value| value.is_a?(Hash) ? value.dig('contextInfo', 'mentionedJID') : nil }.flatten.compact
  end
end
