class Waha::IncomingMessageService
  IGNORED_CHAT_SUFFIXES = %w[@newsletter status@broadcast].freeze
  MEDIA_TYPES = %w[image document audio ptt video sticker].freeze
  SENT_FROM_WHATSAPP_LABEL = 'Enviado pelo WhatsApp'.freeze
  EDITED_LABEL = '✏️ Editada'.freeze

  # `edited_original`, when present, means this message is the edited version of
  # an existing one: we tag its content and quote the original message.
  pattr_initialize [:channel!, :payload!, :edited_original]

  def perform
    return if ignored_chat?
    return if group_message_disabled?
    return if message_already_exists?

    if edited_original
      # An edit reuses the original message's conversation and contact. The edit
      # event (especially one sent from Chatwoot via the API) can carry a
      # different chat id than the original, so re-resolving would spawn a bogus
      # contact/conversation for the same person.
      @conversation = edited_original.conversation
      @contact = @conversation.contact
    else
      @contact_inbox = resolve_contact
      return unless @contact_inbox

      @contact = @contact_inbox.contact
    end

    ActiveRecord::Base.transaction do
      set_conversation unless @conversation
      create_message
    end
  end

  private

  def chat_id
    # `_data.Info.Chat` is always the conversation JID regardless of direction
    # (the contact for incoming DMs, the recipient for messages we sent from the
    # phone, the group for group messages). We fall back to `to`/`from` because
    # for a fromMe message `from` is our own number, not the contact.
    @chat_id ||= payload.dig('_data', 'Info', 'Chat').presence ||
                 (payload['fromMe'] ? payload['to'] : payload['from'])
  end

  def incoming?
    !payload['fromMe']
  end

  def sender_jid
    # In groups, _data.author is the participant who sent; otherwise it's from.
    @sender_jid ||= payload.dig('_data', 'author').presence || payload['from']
  end

  def push_name
    payload.dig('_data', 'Info', 'PushName').presence || payload.dig('_data', 'pushName')
  end

  def source_id
    @source_id ||= payload['id']
  end

  def stanza_id
    @stanza_id ||= source_id.to_s.split('_').last
  end

  def ignored_chat?
    IGNORED_CHAT_SUFFIXES.any? { |suffix| chat_id.to_s.end_with?(suffix) }
  end

  def group_message_disabled?
    chat_id.to_s.end_with?('@g.us') && !channel.groups_enabled
  end

  def message_already_exists?
    inbox.messages.exists?(['source_id LIKE ?', "%_#{stanza_id}"])
  end

  def resolve_contact
    Waha::ContactResolver.new(
      channel: channel,
      jid: chat_id,
      push_name: push_name,
      from_me: payload['fromMe'],
      sender_alt: payload.dig('_data', 'Info', 'SenderAlt')
    ).perform
  end

  def set_conversation
    @conversation = if inbox.lock_to_single_conversation
                      @contact_inbox.conversations.last
                    else
                      @contact_inbox.conversations.where.not(status: :resolved).last
                    end

    return if @conversation

    @conversation = ::Conversation.create!(
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      contact_id: @contact.id,
      contact_inbox_id: @contact_inbox.id
    )
  end

  def create_message
    @message = @conversation.messages.build(
      content: text_content,
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      message_type: incoming? ? :incoming : :outgoing,
      # Outgoing (sent from the phone) has no Chatwoot agent as sender.
      sender: (@contact if incoming?),
      source_id: source_id,
      status: initial_status,
      content_attributes: build_content_attributes,
      additional_attributes: build_additional_attributes
    )

    attach_media if media_message?
    @message.save!
  end

  # For a mirrored outgoing message the payload already carries the WhatsApp ack,
  # so we seed the check state instead of waiting for the next message.ack event.
  def initial_status
    return :sent if incoming?

    case payload['ack']
    when 2 then :delivered
    when 3, 4 then :read
    else :sent
    end
  end

  # Messages sent from the phone/WhatsApp Web have no Chatwoot agent. Storing a
  # sender_name (same mechanism Slack uses) makes the UI label them instead of
  # falling back to the generic "Bot" sender.
  def build_additional_attributes
    attrs = incoming? ? {} : { sender_name: SENT_FROM_WHATSAPP_LABEL }

    # Anchor every edit mirror to the original message's source_id so the whole
    # edit family can be found later (to strike the previous head, and to resolve
    # replies back to the single real WhatsApp message).
    attrs[:edit_of] = edited_original.source_id if edited_original

    attrs
  end

  def text_content
    body = payload['body'].presence
    return body unless edited_original && body

    "#{body} [#{EDITED_LABEL}]"
  end

  def media_message?
    MEDIA_TYPES.include?(payload['type']) && payload['hasMedia']
  end

  def attach_media
    media_url = payload['mediaUrl']
    return if media_url.blank?

    begin
      file = Down.download(media_url, headers: { 'Authorization' => "Bearer #{channel.api_key}" })
      @message.attachments.build(
        account_id: @message.account_id,
        file_type: map_file_type(payload['type']),
        file: {
          io: file,
          filename: file.original_filename,
          content_type: file.content_type
        }
      )
    rescue StandardError => e
      Rails.logger.error "[WAHA] Media download failed for #{source_id}: #{e.message}"
    end
  end

  def map_file_type(type)
    case type
    when 'image', 'sticker' then :image
    when 'audio', 'ptt' then :audio
    when 'video' then :video
    else :file
    end
  end

  def build_content_attributes
    attrs = {}
    reply_stanza = payload.dig('replyTo', 'id')
    if reply_stanza.present?
      quoted = inbox.messages.where('source_id LIKE ?', "%_#{reply_stanza}").first
      attrs[:in_reply_to_external_id] = quoted&.source_id || reply_stanza
    end

    # Store participant name for group messages
    if chat_id.to_s.end_with?('@g.us')
      attrs[:sender_name] = push_name
      attrs[:participant_jid] = sender_jid
    end

    # An edit quotes the original message it replaces, regardless of what the
    # original itself was replying to.
    attrs[:in_reply_to_external_id] = edited_original.source_id if edited_original

    attrs
  end

  def inbox
    @inbox ||= channel.inbox
  end
end
