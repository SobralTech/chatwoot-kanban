# External identities are resolved only through the channel/chat mapping.
# Edit families use native message IDs, independent of provider ID formatting.
module Waha::Anchoring
  module_function

  def external_anchor_source_id(message)
    mappings_for(message).first&.provider_id
  end

  def mappings_for(message)
    anchor = family_anchor_message(message)
    anchor.waha_message_mappings.resolved.where(event_type: :message).order(:part, :id)
  end

  def family_anchor_message(message)
    message.waha_message_mappings.resolved.where(event_type: :edit).first&.anchor_message || message
  end

  def family(inbox, message)
    anchor = family_anchor_message(message)
    mirrors = WahaMessageMapping.resolved.where(anchor_message: anchor, event_type: :edit).select(:message_id)
    inbox.messages.where(id: anchor.id).or(inbox.messages.where(id: mirrors))
  end

  def stanza_of(provider_id)
    provider_id.to_s.split('_').reject { |part| part.include?('@') }.last
  end

  def chat_jid_of(provider_id)
    provider_id.to_s.split('_').find { |part| part.include?('@') }
  end

  def chat_jids(channel, jids)
    normalized = Array(jids).compact.map { |jid| Waha::Jid.phone_jid(jid) || jid }.uniq
    aliases = channel.contact_aliases.where(value: normalized)
    contact_ids = aliases.select(:contact_inbox_id)
    normalized | channel.contact_aliases.where(contact_inbox_id: contact_ids, alias_type: %w[jid lid]).pluck(:value)
  end

  def find_message(channel, provider_id, chat_jid = nil)
    WahaMessageMapping.find_mapping(
      channel: channel, chat_jid: chat_jid || chat_jid_of(provider_id), external_id: stanza_of(provider_id)
    )&.message
  end
end
