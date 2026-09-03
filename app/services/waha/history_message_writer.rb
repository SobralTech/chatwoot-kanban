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
      content: payload['body'].presence,
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
      attrs[:sender_name] = push_name
      attrs[:participant_jid] = sender_jid
      attrs[:participant_phone] = sender_phone
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

  # No extra WAHA call here (bulk import): resolve only what the event already
  # carries, otherwise fall back to the @lid's own digits.
  def sender_phone
    sender_alt = payload.dig('_data', 'Info', 'SenderAlt')
    digits = Waha::Jid.digits(sender_alt) if Waha::Jid.lid?(sender_jid) && sender_alt.to_s.end_with?('@s.whatsapp.net')
    "+#{digits || Waha::Jid.digits(sender_jid)}"
  end

  def inbox
    @inbox ||= channel.inbox
  end
end
