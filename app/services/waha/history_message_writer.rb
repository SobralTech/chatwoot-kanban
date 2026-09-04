class Waha::HistoryMessageWriter
  SENT_FROM_WHATSAPP_LABEL = Waha::IncomingMessageService::SENT_FROM_WHATSAPP_LABEL

  # Writes one WAHA history message into an already-resolved conversation. Initial
  # history is silent, backdated and pre-read; recent gap recovery is backdated
  # but follows the normal message path so it remains actionable. Reply-context
  # reuses the same resolver as the live path. Media is attached later by
  # Waha::HistoryMediaJob (off the import's critical path). Edits/reactions are
  # not reconstructed (MVP).
  # Returns the persisted message.
  pattr_initialize [:channel!, :payload!, :conversation!, { kind: 'initial' }]

  def perform
    Waha::Locking.with_chat_lock(channel, lock_chat_jids) do
      existing = find_canonical_message
      return existing if existing

      ActiveRecord::Base.transaction do
        build_message
        @message.imported = initial_import?
        @message.preserve_conversation_status = gap_fill?
        @message.save!
        record_canonical_mapping!
        @message
      end
    end
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    find_canonical_message
  end

  private

  def stanza
    @stanza ||= Waha::Anchoring.stanza_of(payload['id'])
  end

  def canonical_chat_jid
    conversation.contact_inbox&.source_id || chat_id
  end

  def lock_chat_jids
    candidate_chat_jids
  end

  def candidate_chat_jids
    [conversation.contact_inbox&.source_id, chat_id].compact.uniq
  end

  def find_canonical_message
    return nil if stanza.blank?

    mapping = WahaMessageMapping.find_mapping(
      channel: channel,
      chat_jid: candidate_chat_jids,
      external_id: stanza,
      event_type: :message
    )
    return mapping.message if mapping&.message

    conversation.messages.where("#{Waha::Anchoring::STANZA_SQL} = ?", stanza).first
  end

  def record_canonical_mapping!
    WahaMessageMapping.create_canonical!(
      channel: channel,
      message: @message,
      chat_jid: canonical_chat_jid,
      external_id: stanza,
      direction: incoming? ? :incoming : :outgoing,
      event_type: :message,
      participant_jid: chat_id.to_s.end_with?('@g.us') ? sender_jid : nil
    )
  end

  def build_message
    @message = conversation.messages.build(
      content: text_content,
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      message_type: incoming? ? :incoming : :outgoing,
      sender: incoming? ? conversation.contact : nil,
      source_id: payload['id'],
      status: initial_status,
      created_at: Time.zone.at(payload['timestamp'].to_i),
      content_attributes: build_content_attributes,
      additional_attributes: build_additional_attributes
    )
  end

  def text_content
    converter.content
  end

  # Selection only — download/attach are the live path's concern
  # (Waha::HistoryMediaJob attaches history media later, off the import's
  # critical path), but the same registry still marks an unsupported or
  # otherwise-empty payload instead of writing a blank row.
  def converter
    @converter ||= Waha::MessageConverters::Registry.for(channel: channel, payload: payload)
  end

  def incoming?
    !payload['fromMe']
  end

  # Backdated outgoing history carries its final WhatsApp ack, so we seed the
  # check state directly (same mapping as the live IncomingMessageService).
  def initial_status
    return :sent if incoming?

    case payload['ack']
    when 2 then :delivered
    when 3, 4 then :read
    else :sent
    end
  end

  def build_additional_attributes
    # This durable provenance gives listeners and automation policies a way to
    # distinguish a silent initial backfill from an actionable recent recovery.
    attrs = { 'waha_import_kind' => kind }
    attrs['imported'] = true if initial_import?
    # Phone/WhatsApp-sent outgoing messages have no Chatwoot agent; label them
    # instead of falling back to the generic "Bot" sender.
    attrs['sender_name'] = SENT_FROM_WHATSAPP_LABEL unless incoming?
    attrs
  end

  def build_content_attributes
    attrs = Waha::ReplyContextResolver.new(channel: channel, payload: payload, conversation: conversation).perform
    attrs.merge!(converter.metadata)
    if chat_id.to_s.end_with?('@g.us')
      attrs[:sender_name] = participant_display_name
      attrs[:participant_jid] = sender_jid
      attrs[:participant_phone] = resolve_participant&.phone_number
    end
    attrs
  end

  def chat_id
    @chat_id ||= payload.dig('_data', 'Info', 'Chat').presence ||
                 (payload['fromMe'] ? payload['to'] : payload['from'])
  end

  def sender_jid
    # `participant` is WAHA's normalized group-sender field; _data.author covers
    # engines that don't set it. Outside a group both are absent and `from` applies.
    @sender_jid ||= payload['participant'].presence || payload.dig('_data', 'author').presence || payload['from']
  end

  def push_name
    payload.dig('_data', 'Info', 'PushName').presence || payload.dig('_data', 'pushName')
  end

  # Resolves the group participant to a real Chatwoot contact — deduped per
  # unique participant (ContactResolver short-circuits once their contact
  # exists), so this costs WAHA calls only once per new person, not per message.
  # Purely a display enrichment (structured sender metadata), so a failure here
  # must not block the historical message itself.
  def resolve_participant
    return @resolve_participant if defined?(@resolve_participant)

    @resolve_participant = Waha::ContactResolver.new(
      channel: channel,
      jid: sender_jid,
      push_name: push_name,
      sender_alt: payload.dig('_data', 'Info', 'SenderAlt')
    ).perform&.contact
  rescue StandardError => e
    Rails.logger.error "[WAHA] group participant resolution failed for #{sender_jid}: #{e.message}"
    @resolve_participant = nil
  end

  # A resolved contact always has *some* name (ContactResolver falls back to
  # "+phone"), but the header should stay blank rather than show that phone
  # number twice — Base.vue already falls back to participant_phone alone.
  def participant_display_name
    name = resolve_participant&.name
    name unless name.to_s.start_with?('+')
  end

  def inbox
    @inbox ||= channel.inbox
  end

  def initial_import?
    kind == 'initial'
  end

  def gap_fill?
    kind == 'gap_fill'
  end
end
