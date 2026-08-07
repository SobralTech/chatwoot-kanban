class KanbanCardListener < BaseListener
  def conversation_created(event)
    conversation = event.data[:conversation]
    return if conversation.blank?

    accepting_boards(conversation).each do |kanban_board|
      KanbanCards::EvaluateContactRecurrenceJob.perform_later(
        conversation.id,
        kanban_board.id,
        conversation.inbox_id
      )
    end

    KanbanCards::AutoCreateFromConversationJob.perform_later(conversation.id)
  end

  def message_created(event)
    message = event.data[:message]
    return if ignore_message_created_event?(event)

    conversation = message.conversation
    return if conversation.blank?

    accepting_boards(conversation, message.inbox_id).each do |kanban_board|
      KanbanCards::EvaluateContactRecurrenceJob.perform_later(
        conversation.id,
        kanban_board.id,
        message.inbox_id
      )
    end
  end

  private

  def accepting_boards(conversation, inbox_id = conversation.inbox_id)
    KanbanBoard.accepting_inbox_for_account(conversation.account_id, inbox_id)
  end

  def ignore_message_created_event?(event)
    message = event.data[:message]

    message.blank? || performed_by_automation?(event) || !message.incoming? || message.private? ||
      message.activity? || message.auto_reply_email?
  end

  def performed_by_automation?(event)
    event.data[:performed_by].is_a?(AutomationRule)
  end
end
