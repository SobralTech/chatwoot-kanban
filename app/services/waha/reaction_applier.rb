class Waha::ReactionApplier
  QUOTE_LIMIT = 60

  # Applies a message.reaction payload to the target message (the current member
  # of its edit family): stores the reaction under content_attributes['reactions']
  # keyed by reactor — WhatsApp allows one reaction per person, so a new reaction
  # replaces the previous one naturally — and posts an activity on add/change.
  # Removals (empty text) are silent: the chip disappears, no activity.
  pattr_initialize [:channel!, :target_message!, :payload!]

  def perform
    # WhatsApp discards reactions along with a revoked message; nothing to show.
    return if target_message.content_attributes['deleted']

    emoji = payload.dig('reaction', 'text').to_s
    emoji.empty? ? remove_reaction : apply_reaction(emoji)
  end

  private

  def reactions
    @reactions ||= (target_message.content_attributes['reactions'] || {}).deep_dup
  end

  def remove_reaction
    return unless reactions.key?(reactor_key)

    reactions.delete(reactor_key)
    ActiveRecord::Base.transaction do
      update_target_reactions
      clear_pending_agent
    end
  end

  def apply_reaction(emoji)
    # Idempotent under webhook redelivery: same reactor + same emoji is a no-op
    # (no duplicate activity).
    return if reactions.dig(reactor_key, 'emoji') == emoji

    entry = { 'emoji' => emoji, 'agent_id' => pending_agent&.id, 'name' => reactor_name, 'timestamp' => payload['timestamp'] }
    reactions[reactor_key] = entry
    ActiveRecord::Base.transaction do
      update_target_reactions
      clear_pending_agent
      create_activity(emoji, entry['name'])
    end
  end

  # The update! broadcasts message.updated, so the chip refreshes in realtime.
  def update_target_reactions
    attrs = target_message.content_attributes.except('reactions')
    attrs = attrs.merge('reactions' => reactions) if reactions.present?
    target_message.update!(content_attributes: attrs)
  end

  # "me" is the business number's single reaction slot (any direction); in a
  # group the reactor is the participant, in a DM it's the chat itself.
  def reactor_key
    return 'me' if payload['fromMe']

    payload['participant'].presence || payload['from']
  end

  def reactor_name
    if payload['fromMe']
      pending_agent&.name || I18n.t('conversations.activity.waha_reaction.you')
    elsif payload['participant'].present?
      participant_name
    else
      conversation.contact.name
    end
  end

  # Group participants may not exist as contacts; we only reuse an existing one
  # and fall back to the formatted number — never create a contact for a reaction.
  def participant_name
    contact_inbox = channel.inbox.contact_inboxes.find_by(source_id: reactor_key)
    contact_inbox&.contact&.name || formatted_number(reactor_key)
  end

  def formatted_number(jid)
    digits = jid.to_s.split('@').first.to_s.split(':').first
    digits.present? ? "+#{digits}" : jid.to_s
  end

  # The agent who reacted from Chatwoot, resolved from the marker ReactionService
  # stashed on the family anchor before the PUT. Absent for phone/Web reactions
  # ("Você") and for contact reactions.
  def pending_agent
    return @pending_agent if defined?(@pending_agent)
    return @pending_agent = nil unless payload['fromMe']

    agent_id = anchor_message&.content_attributes&.dig('pending_reaction_agent_id')
    @pending_agent = agent_id.present? ? channel.account.users.find_by(id: agent_id) : nil
  end

  # Consume the marker in the same transaction so it never leaks into a later
  # reaction on the same message.
  def clear_pending_agent
    return unless payload['fromMe']
    return unless anchor_message&.content_attributes&.key?('pending_reaction_agent_id')

    anchor_message.update!(content_attributes: anchor_message.content_attributes.except('pending_reaction_agent_id'))
  end

  # The marker lives on the anchor (the real WhatsApp message), which may differ
  # from the current edit mirror the reaction is displayed on.
  def anchor_message
    return @anchor_message if defined?(@anchor_message)

    anchor_source_id = target_message.additional_attributes['edit_of'].presence
    @anchor_message = anchor_source_id ? channel.inbox.messages.find_by(source_id: anchor_source_id) : target_message
  end

  def create_activity(emoji, author)
    conversation.messages.create!(
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :activity,
      content: I18n.t('conversations.activity.waha_reaction.reacted', author: author, emoji: emoji, quote: quote),
      content_attributes: { waha_reaction: { emoji: emoji, target_message_id: target_message.id } }
    )
  end

  def quote
    text = target_message.content.to_s.strip
    return text.truncate(QUOTE_LIMIT, omission: '…') if text.present?

    media_placeholder
  end

  def media_placeholder
    key = { 'image' => 'photo', 'video' => 'video', 'audio' => 'audio' }.fetch(target_message.attachments.first&.file_type, 'document')
    I18n.t("conversations.activity.waha_reaction.media.#{key}")
  end

  def conversation
    @conversation ||= target_message.conversation
  end
end
