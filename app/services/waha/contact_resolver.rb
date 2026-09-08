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
    existing = identity_candidates(identity)
    # Both of these read the WAHA session, so they run before the transaction
    # opens instead of holding the alias locks across an HTTP call.
    attributes = existing.empty? ? build_contact_attributes(identity[:jid], identity[:lid]) : nil
    enrichment = existing.one? ? build_enrichment(existing.first.contact, identity) : {}

    contact_inbox = upsert_contact_inbox(identity, attributes, enrichment)
    attach_avatar!(contact_inbox.contact, enrichment[:avatar_url]) unless @alias_conflict
    contact_inbox
  end

  private

  def upsert_contact_inbox(identity, contact_attributes, enrichment)
    ActiveRecord::Base.transaction do
      lock_aliases!(identity[:aliases])
      contact_inbox = find_or_create_contact_inbox(identity, contact_attributes)
      unless @alias_conflict
        attach_aliases!(contact_inbox, identity[:aliases])
        promote_phone_identity!(contact_inbox, identity)
        enrich_contact!(contact_inbox.contact, identity, enrichment)
      end
      contact_inbox
    end
  end

  def resolve_group
    existing = channel.inbox.contact_inboxes.find_by(source_id: jid)
    return enrich_group(existing) if existing

    ::ContactInboxWithContactBuilder.new(
      source_id: jid,
      inbox: channel.inbox,
      contact_attributes: build_contact_attributes(jid)
    ).perform
  end

  # Same rule as a person: locating the group's ContactInbox doesn't end the
  # flow. A group first seen while the session couldn't answer picks up its real
  # subject and picture on the next message.
  def enrich_group(contact_inbox)
    contact = contact_inbox.contact
    name = fetch_group_name(jid) if Waha::ContactNaming.fallback_name?(contact.name)
    contact.update!(name: name) if name.present?
    attach_avatar!(contact, fetch_chat_picture(jid)) unless contact.avatar.attached?
    contact_inbox
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

  def enrich_contact!(contact, identity, enrichment)
    name = upgraded_name(contact, enrichment)
    updates = {
      additional_attributes: identity_attributes(contact, identity, (enrichment[:source] if name)),
      custom_attributes: lid_custom_attributes(contact, identity),
      name: name,
      phone_number: missing_phone(contact, identity)
    }.compact
    contact.update!(updates) if updates.any? { |key, value| contact.public_send(key) != value }
  rescue ActiveRecord::RecordInvalid => e
    log_alias_conflict(contact.contact_inboxes.where(inbox: channel.inbox).to_a, e)
  end

  # The ranking decided before the transaction is re-checked against whichever
  # contact actually won the alias lock, so a concurrent resolution can never
  # make us downgrade a name.
  def upgraded_name(contact, enrichment)
    return if enrichment[:name].blank?
    return unless Waha::ContactNaming.better?(enrichment[:source], than: Waha::ContactNaming.source_of(contact))

    enrichment[:name]
  end

  def identity_attributes(contact, identity, name_source)
    attributes = contact.additional_attributes.merge('jid' => identity[:jid])
    attributes['lid'] = identity[:lid] if identity[:lid].present?
    attributes[Waha::ContactNaming::SOURCE_KEY] = name_source if name_source
    attributes
  end

  def missing_phone(contact, identity)
    return if contact.phone_number.present?

    formatted_phone(identity[:jid])
  end

  def lid_custom_attributes(contact, identity)
    return contact.custom_attributes if identity[:lid].blank?

    ensure_lid_attribute_definition
    contact.custom_attributes.merge(LID_ATTRIBUTE_KEY => identity[:lid])
  end

  # Finding a ContactInbox must not end the flow: a contact first seen as a bare
  # phone number, or created while the session couldn't answer, has to pick up a
  # real name and an avatar as soon as WAHA offers them. Both lookups swallow
  # their own failures, and neither ever replaces data that is already as good.
  def build_enrichment(contact, identity)
    enrichment = name_enrichment(contact, identity)
    # Missing-only, like the contact's phone number: an avatar already on the
    # contact (WAHA's or one an agent uploaded) is never overwritten.
    enrichment[:avatar_url] = fetch_chat_picture(jid) unless contact.avatar.attached?
    enrichment.compact
  end

  def name_enrichment(contact, identity)
    current_source = Waha::ContactNaming.source_of(contact)
    # Nothing below the push name can improve on what we have, so we don't spend
    # a WAHA call per message on a contact that is already properly named.
    return {} unless Waha::ContactNaming.better?('push', than: current_source)

    name, source = dm_name(identity[:jid], formatted_phone(identity[:jid]))
    return {} unless Waha::ContactNaming.better?(source, than: current_source)

    { name: name, source: source }
  end

  def attach_avatar!(contact, avatar_url)
    return if avatar_url.blank?

    ::Avatar::AvatarFromUrlJob.perform_later(contact, avatar_url)
  end

  def log_alias_conflict(contact_inboxes, error = nil)
    Waha::Telemetry.emit(
      :contact_identity_conflict, channel: channel, level: :error, reason: error ? :merge_failed : :multiple_claimants,
                                  contact_inbox_ids: contact_inboxes.map(&:id).sort.join('|'), error: error&.class&.name
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
    name, source = dm_name(resolved_jid, formatted_phone(resolved_jid))
    attrs = { name: name, additional_attributes: { Waha::ContactNaming::SOURCE_KEY => source } }
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

  # Direct-conversation naming priority, best evidence first: the name WAHA's
  # contacts registry holds for this person, the push name this event carried,
  # the profile name the registry knows, the formatted phone number and, last,
  # the raw JID.
  # push_name is read only on an incoming message: on a fromMe message the
  # PushName field holds our *own* session profile, so trusting it would rename
  # the contact to the business.
  def dm_name(resolved_jid, phone)
    profile = fetch_contact_profile(resolved_jid)
    return [profile['name'], 'contact'] if profile['name'].present?
    return [push_name, 'push'] if incoming? && push_name.present?
    return [profile['pushname'], 'push'] if profile['pushname'].present?
    return [phone, 'phone'] if phone.present?

    [resolved_jid, 'jid']
  end

  # WAHA's own contact profile cache — populated from the phone's address book
  # and WhatsApp presence data independently of any single message, so it has
  # a name even when the triggering message's own PushName is blank (the norm
  # for history-synced messages). GOWS answers {id, name, pushname}.
  def fetch_contact_profile(contact_jid)
    response = http_client.get("#{channel.session_name}/contacts/#{contact_jid}")
    response.is_a?(Hash) ? response : {}
  rescue StandardError
    {}
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

  def formatted_phone(resolved_jid)
    phone = phone_from_jid(resolved_jid)
    "+#{phone}" if phone.present?
  end

  def http_client
    @http_client ||= Waha::HttpClient.new(channel: channel)
  end
end
# rubocop:enable Metrics/ClassLength
