class Waha::HistoryMessageWriter
  SENT_FROM_WHATSAPP_LABEL = Waha::IncomingMessageService::SENT_FROM_WHATSAPP_LABEL

  # Writes one historical WAHA message into an already-resolved conversation:
  # silent (the `imported` flag skips every live side effect), backdated to the
  # real WhatsApp timestamp, and pre-read. Reply-context reuses the same resolver
  # as the live path. Media is attached later by Waha::HistoryMediaJob (off the
  # import's critical path). Edits/reactions are not reconstructed (MVP).
  # Returns the persisted message.
  pattr_initialize [:channel!, :payload!, :conversation!]

  def perform
    build_message
    @message.imported = true
    @message.save!
    @message
  end

  private

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
    Waha::MentionResolver.new(channel: channel, payload: payload).resolve(payload['body'].presence)
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
    attrs = { 'imported' => true }
    # Phone/WhatsApp-sent outgoing messages have no Chatwoot agent; label them
    # instead of falling back to the generic "Bot" sender.
    attrs['sender_name'] = SENT_FROM_WHATSAPP_LABEL unless incoming?
    attrs
  end

  def build_content_attributes
    attrs = Waha::ReplyContextResolver.new(channel: channel, payload: payload, conversation: conversation).perform
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
  def resolve_participant
    return @resolve_participant if defined?(@resolve_participant)

    @resolve_participant = Waha::ContactResolver.new(
      channel: channel,
      jid: sender_jid,
      push_name: push_name,
      sender_alt: payload.dig('_data', 'Info', 'SenderAlt')
    ).perform&.contact
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
end
