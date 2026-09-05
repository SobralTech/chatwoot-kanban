# Resolves who actually sent a group message (or who a mention/reply points at)
# so it can be stored as structured sender metadata on the message itself.
#
# The group stays the conversation's contact, and a participant without a direct
# conversation has no functional relation to model in Chatwoot, so this never
# creates a Contact or a ContactInbox for them. It reads, in order, the contacts
# this account already knows, WAHA's contacts registry and the push name the
# event carried.
class Waha::ParticipantResolver
  Profile = Struct.new(:name, :phone_number)

  pattr_initialize [:channel!, :jid!, :push_name, :sender_alt]

  def perform
    Profile.new(display_name, phone_number)
  end

  private

  # Lazy on purpose: a participant already known to this account costs no WAHA
  # call at all, which matters because this runs for every group message.
  def display_name
    [method(:known_contact_name), method(:registry_name), -> { push_name }]
      .lazy.filter_map(&:call).reject { |name| Waha::ContactNaming.fallback_name?(name) }.first
  end

  # A contact this account already knows — through a direct conversation, an
  # import or an agent's own edit — is the name an agent expects to read.
  def known_contact_name
    (contact_from_lid || contact_from_aliases || contact_from_phone)&.name
  end

  def contact_from_lid
    return unless Waha::Jid.lid?(jid)

    channel.account.contacts.where("additional_attributes->>'lid' = ?", jid).first
  end

  def contact_from_aliases
    predicate = alias_predicates.reduce(&:or)
    return unless predicate

    channel.contact_aliases.where(predicate).includes(contact_inbox: :contact).first&.contact_inbox&.contact
  end

  def alias_predicates
    table = WahaContactAlias.arel_table
    pairs = [['jid', phone_jid], ['lid', (jid if Waha::Jid.lid?(jid))], ['phone', phone_number]]
    pairs.filter_map do |type, value|
      table[:alias_type].eq(type).and(table[:value].eq(value)) if value.present?
    end
  end

  def contact_from_phone
    return if phone_number.blank?

    channel.account.contacts.find_by(phone_number: phone_number)
  end

  # GOWS answers {id, name, pushname} — the address book name first, the
  # WhatsApp profile name as the weaker fallback.
  def registry_name
    profile = fetch("contacts/#{phone_jid.presence || jid}")
    profile['name'].presence || profile['pushname'].presence
  end

  def phone_number
    return @phone_number if defined?(@phone_number)

    digits = Waha::Jid.digits(phone_jid)
    @phone_number = "+#{digits}" if digits.present?
  end

  def phone_jid
    return @phone_jid if defined?(@phone_jid)

    @phone_jid = Waha::Jid.lid?(jid) ? Waha::Jid.phone_jid(lid_phone_jid) : Waha::Jid.phone_jid(jid)
  end

  # An incoming event already carries the participant's real number in SenderAlt
  # ("558894397552:23@s.whatsapp.net"); only a LID without it needs the session's
  # lid map.
  def lid_phone_jid
    return sender_alt if sender_alt.to_s.end_with?('@s.whatsapp.net')

    fetch("lids/#{jid}")['pn']
  end

  # Everything here enriches a message that must be persisted either way, so a
  # session that cannot answer just leaves the sender less identified.
  def fetch(path)
    response = http_client.get("#{channel.session_name}/#{path}")
    response.is_a?(Hash) ? response : {}
  rescue StandardError
    {}
  end

  def http_client
    @http_client ||= Waha::HttpClient.new(channel: channel)
  end
end
