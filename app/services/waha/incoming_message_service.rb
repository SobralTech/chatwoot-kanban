class Waha::IncomingMessageService
  IGNORED_CHAT_SUFFIXES = %w[@newsletter status@broadcast].freeze
  MEDIA_TYPES = %w[image document audio ptt video sticker].freeze

  pattr_initialize [:channel!, :payload!]

  def perform
    return if ignored_chat?
    return if group_message_disabled?
    return if message_already_exists?

    @contact_inbox = resolve_contact
    return unless @contact_inbox

    @contact = @contact_inbox.contact

    ActiveRecord::Base.transaction do
      set_conversation
      create_message
    end
  end

  private

  def chat_id
    # For DMs, payload['from'] is the contact JID.
    # For groups, payload['from'] is the group JID.
    @chat_id ||= payload.dig('_data', 'chatId') || payload['from']
  end

  def sender_jid
    # In groups, _data.author is the participant who sent; otherwise it's from.
    @sender_jid ||= payload.dig('_data', 'author').presence || payload['from']
  end

  def push_name
    payload.dig('_data', 'pushName')
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
      push_name: push_name
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
      message_type: :incoming,
      sender: @contact,
      source_id: source_id,
      content_attributes: build_content_attributes
    )

    attach_media if media_message?
    @message.save!
  end

  def text_content
    payload['body'].presence
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

    attrs
  end

  def inbox
    @inbox ||= channel.inbox
  end
end
