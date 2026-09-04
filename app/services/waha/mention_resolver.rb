class Waha::MentionResolver
  pattr_initialize [:channel!, :payload!]

  # WhatsApp mentions arrive as a raw "@<lid or phone digits>" token in the body
  # text, resolvable via the message's own mentionedJID list. Resolves each to a
  # Chatwoot contact (creating it if new, same as any other WAHA contact) and
  # swaps in its name.
  def resolve(body)
    return body if body.blank?

    mentioned_jids.reduce(body) do |text, jid|
      contact = resolve_mentioned_contact(jid)
      next text unless contact

      text.gsub("@#{Waha::Jid.digits(jid)}", "@#{contact.name}")
    end
  end

  private

  # Swapping in the mentioned contact's name is a display enrichment; a failure
  # to resolve one mention must not block the rest of the message.
  def resolve_mentioned_contact(jid)
    Waha::ContactResolver.new(channel: channel, jid: jid).perform&.contact
  rescue StandardError => e
    Rails.logger.error "[WAHA] mention resolution failed for #{jid}: #{e.message}"
    nil
  end

  def mentioned_jids
    message_node = payload.dig('_data', 'Message')
    return [] unless message_node.is_a?(Hash)

    message_node.values.filter_map { |value| value.is_a?(Hash) ? value.dig('contextInfo', 'mentionedJID') : nil }.flatten.compact
  end
end
