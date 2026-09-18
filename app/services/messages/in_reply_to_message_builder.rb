class Messages::InReplyToMessageBuilder
  pattr_initialize [:message!, :in_reply_to!, :in_reply_to_external_id!]

  delegate :conversation, to: :message

  def perform
    set_in_reply_to_attribute if @in_reply_to.present? || @in_reply_to_external_id.present?
  end

  private

  # Only fill in the missing counterpart: services (e.g. WAHA) may have already
  # resolved both values with channel-specific logic (edit-family anchors, ghost
  # quotes for messages outside the conversation) that a plain lookup here would
  # clobber or wipe.
  def set_in_reply_to_attribute
    quoted_message = in_reply_to_message

    if conversation.inbox.waha?
      @message.content_attributes[:in_reply_to_external_id] ||= quoted_message&.presented_source_id
      @message.content_attributes[:in_reply_to] ||= quoted_message&.id
    else
      @message.content_attributes[:in_reply_to_external_id] = quoted_message&.presented_source_id
      @message.content_attributes[:in_reply_to] = quoted_message&.id
    end
  end

  def in_reply_to_message
    return conversation.messages.find_by(id: @in_reply_to) if @in_reply_to.present?

    if conversation.inbox.waha?
      quoted = Waha::Anchoring.find_message(conversation.inbox.channel, @in_reply_to_external_id, conversation.contact_inbox.source_id)
      return quoted if quoted&.conversation_id == conversation.id

      return nil
    end

    return conversation.messages.find_by(source_id: @in_reply_to_external_id) if @in_reply_to_external_id

    nil
  end
end
