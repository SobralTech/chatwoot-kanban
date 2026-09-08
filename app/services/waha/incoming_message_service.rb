# rubocop:disable Metrics/ClassLength
class Waha::IncomingMessageService
  SENT_FROM_WHATSAPP_LABEL = 'Enviado pelo WhatsApp'.freeze
  EDITED_LABEL = '✏️ Editada'.freeze

  # `edited_original`, when present, means this message is the edited version of
  # an existing one: we tag its content and quote the original message.
  # `media_terminal`, when true, means the caller already exhausted the media
  # download retries for this event: skip the network attempt and persist with
  # a visible fallback instead of failing (and retrying) again.
  pattr_initialize [:channel!, :payload!, :edited_original, :media_terminal]

  def perform
    policy = Waha::InboundEventPolicy.message(chat_id, groups_enabled: channel.groups_enabled)
    Waha::InboundEventPolicy.observe(channel: channel, event: 'message.any', decision: policy)
    return if policy.action == :ignore

    existing = find_canonical_message
    return existing if existing

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

    existing = find_canonical_message
    return existing if existing

    # Downloading media and resolving @mentions can each block on a WAHA call, so
    # both happen before the transaction opens rather than pinning a connection
    # for the whole fetch.
    converter.download
    @text_content = build_text_content
    persist
  end

  private

  def persist
    Waha::Locking.with_chat_lock(channel, lock_chat_jids) do
      # Re-check under lock: the download above can take up to a minute, and the
      # same event can be in flight twice (Sidekiq delivers at least once, and WAHA
      # retries webhooks it considers failed) or race with history import.
      existing = find_canonical_message
      return existing if existing

      ActiveRecord::Base.transaction do
        set_conversation unless @conversation
        create_message
        record_canonical_mapping!
        clear_pending_editor
        clear_migrated_reactions
        @message
      end
    end
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    # The database unique index on waha_message_mappings is the final guarantee:
    # if concurrent execution bypassed the lock or raced within it, the loser
    # transaction was rolled back, leaving zero duplicate messages in the DB.
    # Return the winning persisted message idempotently.
    find_canonical_message || raise
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

  # Resolves the group participant who actually sent this message. The group
  # itself is the conversation's contact, so this only produces the structured
  # sender metadata stored on the message — no ContactInbox is created for
  # someone who has no direct conversation. Purely a display enrichment, so a
  # failure here must not block the message itself.
  def resolve_participant
    return @resolve_participant if defined?(@resolve_participant)

    @resolve_participant = Waha::ParticipantResolver.new(
      channel: channel,
      jid: sender_jid,
      push_name: (push_name if incoming?),
      sender_alt: payload.dig('_data', 'Info', 'SenderAlt')
    ).perform
  rescue StandardError => e
    Rails.logger.error "[WAHA] group participant resolution failed for #{sender_jid}: #{e.message}"
    @resolve_participant = nil
  end

  def source_id
    @source_id ||= payload['id']
  end

  def stanza
    @stanza ||= Waha::Anchoring.stanza_of(source_id)
  end

  def canonical_chat_jid
    @conversation&.contact_inbox&.source_id || @contact_inbox&.source_id || chat_id
  end

  def candidate_chat_jids
    [@conversation&.contact_inbox&.source_id, @contact_inbox&.source_id, chat_id].compact.uniq
  end

  def lock_chat_jids
    candidate_chat_jids
  end

  def event_type
    edited_original ? :edit : :message
  end

  def find_canonical_message
    return nil if stanza.blank?

    mapping = WahaMessageMapping.find_mapping(
      channel: channel,
      chat_jid: candidate_chat_jids,
      external_id: stanza,
      event_type: event_type
    )
    mapping&.message
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
      status: initial_status,
      content_attributes: build_content_attributes,
      additional_attributes: build_additional_attributes
    )

    converter.attach(@message)
    @message.save!
  end

  def converter
    @converter ||= Waha::MessageConverters::Registry.for(channel: channel, payload: payload, terminal: media_terminal)
  end

  # chat_jid comes from the conversation's contact_inbox rather than this
  # payload's own chat_id: a DM can carry an @lid one message and its resolved
  # @c.us the next (ContactResolver#resolve_jid finds the same contact_inbox
  # either way), and the canonical mapping must not fragment one real chat
  # across two chat_jid values depending on which shape a given event happened
  # to carry.
  def record_canonical_mapping!
    WahaMessageMapping.create_canonical!(
      channel: channel,
      message: @message,
      chat_jid: canonical_chat_jid,
      external_id: stanza,
      direction: incoming? ? :incoming : :outgoing,
      event_type: event_type,
      provider_id: source_id,
      anchor_message: (Waha::Anchoring.family_anchor_message(edited_original) if edited_original),
      participant_jid: chat_id.to_s.end_with?('@g.us') ? sender_jid : nil
    )
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
    if incoming? || (edited_original && pending_editor)
      {}
    else
      { sender_name: SENT_FROM_WHATSAPP_LABEL }
    end
  end

  def build_text_content
    body = converter.content
    return body unless edited_original && body

    "#{body} [#{EDITED_LABEL}]"
  end

  def build_content_attributes
    attrs = Waha::ReplyContextResolver.new(channel: channel, payload: payload, conversation: @conversation).perform
    attrs.merge!(converter.metadata)

    # Store the structured group sender — never a prefix on the message body.
    if chat_id.to_s.end_with?('@g.us')
      attrs[:sender_name] = resolve_participant&.name
      attrs[:participant_jid] = sender_jid
      attrs[:participant_phone] = resolve_participant&.phone_number
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

    family = Waha::Anchoring.family(inbox, edited_original)
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
    attrs[:in_reply_to_external_id] = Waha::Anchoring.external_anchor_source_id(edited_original)
    attrs[:reactions] = previous_reactions_holder.content_attributes['reactions'] if previous_reactions_holder
  end

  def inbox
    @inbox ||= channel.inbox
  end
end
# rubocop:enable Metrics/ClassLength
