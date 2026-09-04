# rubocop:disable Metrics/ClassLength
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
  # Identity resolution and Contact/ContactInbox creation are core: a failure
  # here (e.g. the WAHA session being unreachable) must reach the caller so the
  # job retries, instead of being absorbed into a silently dropped message.
  def perform
    return resolve_group if Waha::Jid.group?(jid)

    identity = resolve_identity
    contact_attributes = build_contact_attributes(identity[:jid], identity[:lid]) unless identity_candidates(identity).any?

    ActiveRecord::Base.transaction do
      lock_aliases!(identity[:aliases])
      contact_inbox = find_or_create_contact_inbox(identity, contact_attributes)
      unless @alias_conflict
        attach_aliases!(contact_inbox, identity[:aliases])
        promote_phone_identity!(contact_inbox, identity)
        enrich_alias_metadata!(contact_inbox.contact, identity)
      end
      contact_inbox
    end
  end

  private

  def resolve_group
    existing = channel.inbox.contact_inboxes.find_by(source_id: jid)
    return existing if existing

    ::ContactInboxWithContactBuilder.new(
      source_id: jid,
      inbox: channel.inbox,
      contact_attributes: build_contact_attributes(jid)
    ).perform
  end

  def resolve_identity
    phone_jid, lid = if Waha::Jid.lid?(jid)
                       [Waha::Jid.phone_jid(resolve_lid_to_cus), jid]
                     else
                       [Waha::Jid.phone_jid(jid), resolve_phone_to_lid(jid)]
                     end
    phone_jid = nil if session_number?(phone_jid)
    resolved_jid = phone_jid.presence || jid

    { jid: resolved_jid, lid: lid.presence, aliases: aliases_for(phone_jid, lid) }
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

  def resolve_phone_to_lid(phone_jid)
    return unless Waha::Jid.phone?(phone_jid)

    http_client.get("#{channel.session_name}/lids/pn/#{phone_jid}")&.dig('lid')
  rescue CustomExceptions::Waha::ApiError => e
    raise unless e.message.include?('(HTTP 404)')

    nil
  end

  def aliases_for(phone_jid, lid)
    aliases = []
    aliases << ['jid', phone_jid] if phone_jid.present?
    aliases << ['lid', lid] if lid.present?
    phone = phone_from_jid(phone_jid)
    aliases << ['phone', "+#{phone}"] if phone.present?
    aliases.uniq
  end

  def lock_aliases!(aliases)
    aliases.sort.each do |type, value|
      key = "waha-contact-alias:#{channel.id}:#{type}:#{value}"
      quoted_key = ActiveRecord::Base.connection.quote(key)
      ActiveRecord::Base.connection.execute("SELECT pg_advisory_xact_lock(hashtextextended(#{quoted_key}, 0))")
    end
  end

  def find_or_create_contact_inbox(identity, contact_attributes)
    candidates = identity_candidates(identity)
    return candidates.first if candidates.one?

    if candidates.many?
      @alias_conflict = true
      log_alias_conflict(candidates)
      return candidates.find { |candidate| candidate.source_id == jid } || candidates.first
    end

    ::ContactInboxWithContactBuilder.new(
      source_id: identity[:jid],
      inbox: channel.inbox,
      contact_attributes: contact_attributes
    ).perform
  end

  def identity_candidates(identity)
    alias_candidates(identity[:aliases]) | legacy_candidates(identity)
  end

  def alias_candidates(aliases)
    table = WahaContactAlias.arel_table
    predicate = aliases.map { |type, value| table[:alias_type].eq(type).and(table[:value].eq(value)) }.reduce(&:or)
    return [] unless predicate

    channel.contact_aliases.where(predicate).includes(:contact_inbox).map(&:contact_inbox)
  end

  def legacy_candidates(identity)
    source_ids = [jid, identity[:jid], identity[:lid]].compact.uniq
    phone = phone_from_jid(identity[:jid])
    scope = channel.inbox.contact_inboxes.left_joins(:contact)
    candidates = scope.where(source_id: source_ids)
    candidates = candidates.or(scope.where(contacts: { phone_number: "+#{phone}" })) if phone.present?
    candidates.to_a
  end

  def attach_aliases!(contact_inbox, aliases)
    aliases.each do |type, value|
      channel.contact_aliases.find_or_create_by!(alias_type: type, value: value) do |contact_alias|
        contact_alias.contact_inbox = contact_inbox
      end
    end
  end

  def promote_phone_identity!(contact_inbox, identity)
    return unless Waha::Jid.lid?(contact_inbox.source_id) && Waha::Jid.phone?(identity[:jid])

    contact_inbox.update!(source_id: identity[:jid])
  rescue ActiveRecord::RecordInvalid => e
    log_alias_conflict([contact_inbox], e)
  end

  # rubocop:disable Metrics/AbcSize
  def enrich_alias_metadata!(contact, identity)
    phone = phone_from_jid(identity[:jid])
    attributes = contact.additional_attributes.merge('jid' => identity[:jid])
    custom_attributes = contact.custom_attributes
    if identity[:lid].present?
      ensure_lid_attribute_definition
      attributes['lid'] = identity[:lid]
      custom_attributes = custom_attributes.merge(LID_ATTRIBUTE_KEY => identity[:lid])
    end

    updates = { additional_attributes: attributes, custom_attributes: custom_attributes }
    updates[:phone_number] = "+#{phone}" if contact.phone_number.blank? && phone.present?
    contact.update!(updates) if updates.any? { |key, value| contact.public_send(key) != value }
  rescue ActiveRecord::RecordInvalid => e
    log_alias_conflict(contact.contact_inboxes.where(inbox: channel.inbox).to_a, e)
  end
  # rubocop:enable Metrics/AbcSize

  def log_alias_conflict(contact_inboxes, error = nil)
    Rails.logger.error(
      "[WAHA] contact alias conflict channel=#{channel.id} contact_inbox_ids=#{contact_inboxes.map(&:id).sort.join(',')} error=#{error&.class&.name}"
    )
  end

  def build_contact_attributes(resolved_jid, lid = nil)
    if Waha::Jid.group?(resolved_jid)
      group_contact_attributes(resolved_jid)
    else
      dm_contact_attributes(resolved_jid, lid)
    end
  end

  def dm_contact_attributes(resolved_jid, lid = nil)
    phone = phone_from_jid(resolved_jid)
    # push_name only names the contact on incoming messages. On a fromMe message
    # PushName is our own profile name, so we skip straight to the contacts
    # lookup. History-synced messages carry no PushName at all (GOWS doesn't
    # persist it per message), so that lookup is the common path there too.
    name = (incoming? && push_name.presence) || fetch_contact_name(resolved_jid) || (phone ? "+#{phone}" : resolved_jid)
    attrs = { name: name, additional_attributes: {} }
    attrs[:phone_number] = "+#{phone}" if phone
    attrs[:avatar_url] = fetch_chat_picture(jid)
    attrs[:additional_attributes][:jid] = resolved_jid
    if lid.present?
      attrs[:additional_attributes][:lid] = lid
      attrs[:custom_attributes] = { LID_ATTRIBUTE_KEY => lid }
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

  # WAHA's own contact profile cache — populated from the phone's address book
  # and WhatsApp presence data independently of any single message, so it has
  # a name even when the triggering message's own PushName is blank (the norm
  # for history-synced messages).
  def fetch_contact_name(contact_jid)
    fetch("contacts/#{contact_jid}", 'pushname', 'name')
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
    resolved_jid.to_s.split('@').first if resolved_jid.to_s.include?('@c.us')
  end

  def http_client
    @http_client ||= Waha::HttpClient.new(channel: channel)
  end
end
# rubocop:enable Metrics/ClassLength
