class KanbanCardListener < BaseListener
  def conversation_created(event)
    conversation = event.data[:conversation]
    return if conversation.blank?

    KanbanCards::AutoCreateFromConversationJob.perform_later(conversation.id)
  end
end
