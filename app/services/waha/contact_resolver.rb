class Waha::ContactResolver
  pattr_initialize [:channel!, :jid!, :push_name]

  # Returns a ContactInbox for the given JID, creating contact if needed.
  def perform
    resolved_jid = resolve_jid
    contact_attrs = build_contact_attributes(resolved_jid)
    ::ContactInboxWithContactBuilder.new(
      source_id: resolved_jid,
      inbox: channel.inbox,
      contact_attributes: contact_attrs
    ).perform
  rescue StandardError => e
    Rails.logger.error "[WAHA] ContactResolver error for #{jid}: #{e.message}"
    nil
  end

  private

  # Resolve @lid JIDs to their real @c.us equivalent via WAHA API.
  def resolve_jid
    return jid unless jid.end_with?('@lid')

    response = http_client.get("#{channel.session_name}/contacts/#{jid}")
    response&.dig('id') || jid
  rescue StandardError
    jid
  end

  def build_contact_attributes(resolved_jid)
    if resolved_jid.end_with?('@g.us')
      group_contact_attributes(resolved_jid)
    else
      dm_contact_attributes(resolved_jid)
    end
  end

  def dm_contact_attributes(resolved_jid)
    phone = phone_from_jid(resolved_jid)
    name = push_name.presence || (phone ? "+#{phone}" : resolved_jid)
    attrs = { name: name, additional_attributes: {} }
    attrs[:phone_number] = "+#{phone}" if phone
    attrs[:additional_attributes][:jid] = resolved_jid
    attrs[:additional_attributes][:lid] = jid if jid.end_with?('@lid')
    attrs
  end

  def group_contact_attributes(group_jid)
    group_name = fetch_group_name(group_jid)
    {
      name: group_name || group_jid,
      additional_attributes: { jid: group_jid, is_group: true }
    }
  end

  def fetch_group_name(group_jid)
    response = http_client.get("#{channel.session_name}/groups/#{group_jid}")
    response&.dig('subject')
  rescue StandardError
    nil
  end

  def phone_from_jid(resolved_jid)
    resolved_jid.split('@').first if resolved_jid.include?('@c.us')
  end

  def http_client
    @http_client ||= Waha::HttpClient.new(channel: channel)
  end
end
