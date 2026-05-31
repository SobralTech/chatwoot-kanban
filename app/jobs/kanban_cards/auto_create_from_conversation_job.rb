class KanbanCards::AutoCreateFromConversationJob < ApplicationJob
  queue_as :low

  def perform(conversation_id)
    conversation = Conversation.find_by(id: conversation_id)
    return if conversation.blank?

    KanbanCards::AutoCreateFromConversationService.new(conversation).perform!
  end
end
