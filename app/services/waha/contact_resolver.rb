class Waha::ContactResolver
  LID_ATTRIBUTE_KEY = 'whatsapp_lid'.freeze

  pattr_initialize [:channel!, :jid!, :push_name, :from_me, :sender_alt, :recipient_alt]

  # Builds a resolver straight from a WAHA message payload — the live and the
  # import path both dig the same five fields out of the same engine-specific
  # paths, so the shape is owned here.
  def self.from_payload(channel:, jid:, payload:)
    new(
      channel: channel,
      jid: jid,
      push_name: payload.dig('_data', 'Info', 'PushName').presence || payload.dig('_data', 'pushName'),
      from_me: payload['fromMe'],
      sender_alt: payload.dig('_data', 'Info', 'SenderAlt'),
      recipient_alt: payload.dig('_data', 'Info', 'RecipientAlt')
    )
  end

  # Returns a ContactInbox for the given JID, creating contact if needed.
  def perform
    resolved_jid = resolve_jid
    # The builder discards contact_attributes when the contact_inbox already
    # exists, so short-circuit before building them — otherwise every message
    # from a known contact pays for an avatar (and group name) fetch against the
    # shared WAHA session for nothing.
    existing = channel.inbox.contact_inboxes.find_by(source_id: resolved_jid)
    return existing if existing

    ::ContactInboxWithContactBuilder.new(
      source_id: resolved_jid,
      inbox: channel.inbox,
      contact_attributes: build_contact_attributes(resolved_jid)
    ).perform
  rescue StandardError => e
    Rails.logger.error "[WAHA] ContactResolver error for #{jid}: #{e.message}"
    nil
  end

  private

  # Resolve @lid JIDs to their real @c.us equivalent.
  def resolve_jid
    return jid unless Waha::Jid.lid?(jid)

    resolved = resolve_lid_to_cus
    # Guard: never map a contact onto our own session number.
    return jid if resolved.blank? || session_number?(resolved)

    resolved
  rescue StandardError
    jid
  end

  def resolve_lid_to_cus
    # Fast path: an incoming message carries the contact's real number in
    # SenderAlt (e.g. "558894397552:23@s.whatsapp.net"). For fromMe messages
    # SenderAlt is our own number; the contact (the recipient) sits in
    # RecipientAlt instead, so we read that mirror field when we sent it.
    return swhatsapp_to_cus(sender_alt) if incoming? && sender_alt.to_s.end_with?('@s.whatsapp.net')
    return swhatsapp_to_cus(recipient_alt) if from_me && recipient_alt.to_s.end_with?('@s.whatsapp.net')

    # Fallback: ask WAHA to map the lid to a phone number (@c.us).
    response = http_client.get("#{channel.session_name}/lids/#{jid}")
    response&.dig('pn')
  end

  def build_contact_attributes(resolved_jid)
    if Waha::Jid.group?(resolved_jid)
      group_contact_attributes(resolved_jid)
    else
      dm_contact_attributes(resolved_jid)
    end
  end

  def dm_contact_attributes(resolved_jid)
    phone = phone_from_jid(resolved_jid)
    # push_name only names the contact on incoming messages. On a fromMe message
    # PushName is our own profile name, so we fall back to the phone number and
    # let a later incoming message fill in the real name.
    name = (incoming? && push_name.presence) || (phone ? "+#{phone}" : resolved_jid)
    attrs = { name: name, additional_attributes: {} }
    attrs[:phone_number] = "+#{phone}" if phone
    attrs[:avatar_url] = fetch_chat_picture(jid)
    attrs[:additional_attributes][:jid] = resolved_jid
    if Waha::Jid.lid?(jid)
      attrs[:additional_attributes][:lid] = jid
      attrs[:custom_attributes] = { LID_ATTRIBUTE_KEY => jid }
      ensure_lid_attribute_definition
    end
    attrs
  end

  # The sidebar only renders custom attributes that have a matching definition,
  # so we make sure one exists for the account (idempotent) before storing the lid.
  def ensure_lid_attribute_definition
    channel.account.custom_attribute_definitions.find_or_create_by!(
      attribute_key: LID_ATTRIBUTE_KEY,
      attribute_model: :contact_attribute
    ) do |definition|
      definition.attribute_display_name = 'WhatsApp LID'
      definition.attribute_display_type = :text
    end
  end

  def group_contact_attributes(group_jid)
    {
      name: fetch_group_name(group_jid) || group_jid,
      identifier: group_jid,
      avatar_url: fetch_chat_picture(group_jid),
      additional_attributes: { jid: group_jid, is_group: true }
    }
  end

  # WEBJS/NOWEB engines return the group name under `subject`; the GOWS engine
  # returns the raw Go struct with a PascalCase `Name` field instead.
  def fetch_group_name(group_jid)
    fetch("groups/#{group_jid}", 'subject', 'Name')
  end

  def fetch_chat_picture(chat_jid)
    fetch("chats/#{chat_jid}/picture", 'url')
  end

  # Optional session lookups: a miss (or an unreachable session) just means we
  # fall back to the JID, so it must never fail the resolution.
  def fetch(path, *keys)
    response = http_client.get("#{channel.session_name}/#{path}")
    keys.lazy.filter_map { |key| response&.dig(key).presence }.first
  rescue StandardError
    nil
  end

  def incoming?
    !from_me
  end

  # "558894397552:23@s.whatsapp.net" -> "558894397552@c.us"
  def swhatsapp_to_cus(raw)
    digits = Waha::Jid.digits(raw)
    digits.present? ? "#{digits}@c.us" : nil
  end

  def session_number?(cus_jid)
    return false if channel.phone_number.blank?

    only_digits(cus_jid) == only_digits(channel.phone_number)
  end

  def only_digits(str)
    str.to_s.gsub(/\D/, '')
  end

  def phone_from_jid(resolved_jid)
    resolved_jid.split('@').first if resolved_jid.include?('@c.us')
  end

  def http_client
    @http_client ||= Waha::HttpClient.new(channel: channel)
  end
end
