class KanbanCards::EvaluateContactRecurrenceJob < ApplicationJob
  queue_as :low

  def perform(conversation_id, kanban_board_id, inbox_id = nil)
    conversation = Conversation.find_by(id: conversation_id)
    kanban_board = KanbanBoard.find_by(id: kanban_board_id)
    return if conversation.blank? || kanban_board.blank?

    inbox = Inbox.find_by(id: inbox_id) if inbox_id.present?
    inbox ||= conversation.inbox

    KanbanCards::EvaluateContactRecurrenceService.new(
      conversation: conversation,
      kanban_board: kanban_board,
      inbox: inbox
    ).perform!
  end
end
