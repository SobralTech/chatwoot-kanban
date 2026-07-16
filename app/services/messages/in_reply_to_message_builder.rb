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
    @message.content_attributes[:in_reply_to_external_id] ||= in_reply_to_message.try(:source_id)
    @message.content_attributes[:in_reply_to] ||= in_reply_to_message.try(:id)
  end

  def in_reply_to_message
    return conversation.messages.find_by(id: @in_reply_to) if @in_reply_to.present?

    return conversation.messages.find_by(source_id: @in_reply_to_external_id) if @in_reply_to_external_id

    nil
  end
end
