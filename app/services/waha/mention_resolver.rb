class Waha::MentionResolver
  pattr_initialize [:channel!, :payload!]

  # WhatsApp mentions arrive as a raw "@<lid or phone digits>" token in the body
  # text, resolvable via the message's own mentionedJID list. Resolves each to a
  # readable name — a mentioned participant needs no Chatwoot identity of their
  # own — and swaps it in.
  def resolve(body)
    return body if body.blank?

    mentioned_jids.reduce(body) do |text, jid|
      name = resolve_mentioned_name(jid)
      next text if name.blank?

      text.gsub("@#{Waha::Jid.digits(jid)}", "@#{name}")
    end
  end

  private

  # Swapping in the mentioned person's name is a display enrichment; a failure
  # to resolve one mention must not block the rest of the message.
  def resolve_mentioned_name(jid)
    Waha::ParticipantResolver.new(channel: channel, jid: jid).perform.name
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
