class Waha::IncomingMessageService
  IGNORED_CHAT_SUFFIXES = %w[@newsletter status@broadcast].freeze
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

    # Downloading media and resolving @mentions can each block on a WAHA call, so
    # both happen before the transaction opens rather than pinning a connection
    # for the whole fetch.
    media_attacher.download
    @text_content = build_text_content
    persist
  end

  private

  def persist
    ActiveRecord::Base.transaction do
      # Re-check under the transaction: the download above can take up to a minute,
      # and the same event can be in flight twice (Sidekiq delivers at least once,
      # and WAHA retries webhooks it considers failed). Checking again here narrows
      # the window between the dedupe check and the insert to the transaction itself.
      next if message_already_exists?

      set_conversation unless @conversation
      create_message
      clear_pending_editor
      clear_migrated_reactions
    end
  end

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
    # `participant` is WAHA's normalized group-sender field; _data.author covers
    # engines that don't set it. Outside a group both are absent and `from` applies.
    @sender_jid ||= payload['participant'].presence || payload.dig('_data', 'author').presence || payload['from']
  end

  def push_name
    payload.dig('_data', 'Info', 'PushName').presence || payload.dig('_data', 'pushName')
  end

  # The contact's real number behind a group sender's @lid, when WhatsApp hands
  # it to us directly on the same event (no extra WAHA call). Falls back to the
  # @lid's own digits — not a phone number, but still a stable, displayable id.
  def sender_phone
    sender_alt = payload.dig('_data', 'Info', 'SenderAlt')
    digits = Waha::Jid.digits(sender_alt) if Waha::Jid.lid?(sender_jid) && sender_alt.to_s.end_with?('@s.whatsapp.net')
    "+#{digits || Waha::Jid.digits(sender_jid)}"
  end

  def source_id
    @source_id ||= payload['id']
  end

  def ignored_chat?
    Channel::Waha::IGNORED_CHAT_SUFFIXES.any? { |suffix| chat_id.to_s.end_with?(suffix) }
  end

  def group_message_disabled?
    chat_id.to_s.end_with?('@g.us') && !channel.groups_enabled
  end

  def message_already_exists?
    Waha::Anchoring.by_stanza(inbox, source_id).exists?
  end

  def resolve_contact
    Waha::ContactResolver.from_payload(channel: channel, jid: chat_id, payload: payload).perform
  end

  # WAHA has no UI toggle for `lock_to_single_conversation`, so we hardcode the
  # single-conversation behavior here: always reuse the contact's last
  # conversation (Message#reopen_conversation reopens it if resolved) instead
  # of spawning a new one.
  def set_conversation
    # A contact sending several messages in a row is the normal case on WhatsApp,
    # and those arrive as separate webhooks processed by separate workers. Without
    # this lock each of them finds no conversation and creates one, splitting the
    # contact across duplicates. The contact_inbox row is the natural serialization
    # point for "this contact in this inbox" and is held only for this transaction.
    @contact_inbox.lock!
    @conversation = @contact_inbox.conversations.last

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
      content: @text_content,
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      message_type: incoming? ? :incoming : :outgoing,
      sender: message_sender,
      source_id: source_id,
      status: initial_status,
      content_attributes: build_content_attributes,
      additional_attributes: build_additional_attributes
    )

    media_attacher.attach_to(@message)
    @message.save!
  end

  def media_attacher
    @media_attacher ||= Waha::MediaAttacher.new(channel: channel, payload: payload)
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
  # Incoming messages are authored by the contact. An outgoing edit made from
  # Chatwoot is authored by the agent who clicked edit (stashed on the original by
  # EditMessageService); a phone-sent message/edit has no Chatwoot sender.
  def message_sender
    return @contact if incoming?

    pending_editor
  end

  # The agent who clicked edit, resolved from the marker EditMessageService left
  # on the original message. Absent for phone-side edits.
  def pending_editor
    return @pending_editor if defined?(@pending_editor)

    editor_id = edited_original&.content_attributes&.dig('pending_edited_by_id')
    @pending_editor = editor_id.present? ? inbox.account.users.find_by(id: editor_id) : nil
  end

  # Consume the marker so it never leaks into a later edit of the same message.
  def clear_pending_editor
    return unless edited_original&.content_attributes&.key?('pending_edited_by_id')

    edited_original.update!(
      content_attributes: edited_original.content_attributes.except('pending_edited_by_id')
    )
  end

  def build_additional_attributes
    # Incoming, or an agent-attributed edit: the sender association already names
    # the author, so no sender_name override is needed. Everything else outgoing
    # (a phone-sent message or a phone-side edit) keeps the WhatsApp label.
    attrs = if incoming? || (edited_original && pending_editor)
              {}
            else
              { sender_name: SENT_FROM_WHATSAPP_LABEL }
            end

    # Anchor every edit mirror to the original message's source_id so the whole
    # edit family can be found later (to strike the previous head, and to resolve
    # replies back to the single real WhatsApp message).
    attrs[:edit_of] = edited_original.source_id if edited_original

    attrs
  end

  def build_text_content
    body = payload['body'].presence
    body = resolve_mentions(body) if body
    return body unless edited_original && body

    "#{body} [#{EDITED_LABEL}]"
  end

  # WhatsApp mentions arrive as a raw "@<lid or phone digits>" token in the body
  # text, resolvable via the message's own mentionedJID list. We resolve each to
  # a Chatwoot contact (creating it if new, same as any other WAHA contact) and
  # swap in its name.
  def resolve_mentions(body)
    mentioned_jids.reduce(body) do |text, jid|
      contact = Waha::ContactResolver.new(channel: channel, jid: jid).perform&.contact
      next text unless contact

      text.gsub("@#{Waha::Jid.digits(jid)}", "@#{contact.name}")
    end
  end

  def mentioned_jids
    message_node = payload.dig('_data', 'Message')
    return [] unless message_node.is_a?(Hash)

    message_node.values.filter_map { |value| value.is_a?(Hash) ? value.dig('contextInfo', 'mentionedJID') : nil }.flatten.compact
  end

  def build_content_attributes
    attrs = Waha::ReplyContextResolver.new(channel: channel, payload: payload, conversation: @conversation).perform

    # Store participant name for group messages
    if chat_id.to_s.end_with?('@g.us')
      attrs[:sender_name] = push_name
      attrs[:participant_jid] = sender_jid
      attrs[:participant_phone] = sender_phone
    end

    merge_edit_context(attrs)

    attrs
  end

  # Reactions follow "the message" as the user sees it: on every edit they
  # migrate from the previous family head (now struck through, found via the
  # family anchor since the reactions may sit on any earlier mirror) to the new
  # mirror, so the chips never duplicate on screen.
  def previous_reactions_holder
    return @previous_reactions_holder if defined?(@previous_reactions_holder)
    return @previous_reactions_holder = nil unless edited_original

    family = Waha::Anchoring.family(inbox, Waha::Anchoring.anchor_source_id(edited_original))
    @previous_reactions_holder = family.find { |member| member.content_attributes['reactions'].present? }
  end

  def clear_migrated_reactions
    return unless previous_reactions_holder

    previous_reactions_holder.update!(
      content_attributes: previous_reactions_holder.content_attributes.except('reactions')
    )
  end

  # An edit mirror quotes the version it replaces (the struck-through previous
  # head), regardless of what the original itself was replying to — the reply
  # context stays visible on the family's original bubble.
  def merge_edit_context(attrs)
    return unless edited_original

    attrs.delete(:in_reply_to_snapshot)
    attrs[:in_reply_to] = Waha::ReplyContextResolver.family_head(inbox, edited_original).id
    attrs[:in_reply_to_external_id] = edited_original.source_id
    attrs[:reactions] = previous_reactions_holder.content_attributes['reactions'] if previous_reactions_holder
  end

  def inbox
    @inbox ||= channel.inbox
  end
end
