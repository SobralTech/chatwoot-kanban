class KanbanCardListener < BaseListener
  # The four conversation attributes an entry rule can read. Inbox is not among them: a
  # conversation never changes inbox, so only creation can bring one into scope.
  ENTRY_RULE_ATTRIBUTES = %w[assignee_id team_id label_list priority].freeze

  def conversation_created(event)
    conversation = event.data[:conversation]
    return if conversation.blank?

    recurrence_enabled_boards(conversation).each do |kanban_board|
      KanbanCards::EvaluateContactRecurrenceJob.perform_later(
        conversation.id,
        kanban_board.id,
        conversation.inbox_id
      )
    end

    KanbanCards::AutoCreateFromConversationJob.perform_later(conversation.id)
  end

  # An entry rule reads labels, assignee, team and priority, and none of those are set when
  # the conversation is created -- routing and the agent fill them in later. So the rules
  # are re-checked on every update that touches one, and the card is created the first time
  # a conversation matches.
  #
  # This runs inline on every conversation update in the account, so it drops the ones that
  # cannot change the answer before reaching the queue.
  def conversation_updated(event)
    conversation = event.data[:conversation]
    return if conversation.blank?
    return unless Array(event.data[:changed_attributes]&.keys).map(&:to_s).intersect?(ENTRY_RULE_ATTRIBUTES)
    return unless KanbanBoardEntryRule.active_for_account?(conversation.account_id)

    KanbanCards::AutoCreateFromConversationJob.perform_later(conversation.id)
  end

  def message_created(event)
    message = event.data[:message]
    return if ignore_message_created_event?(event)

    conversation = message.conversation
    return if conversation.blank?

    recurrence_enabled_boards(conversation, message.inbox_id).each do |kanban_board|
      KanbanCards::EvaluateContactRecurrenceJob.perform_later(
        conversation.id,
        kanban_board.id,
        message.inbox_id
      )
    end
  end

  private

  def recurrence_enabled_boards(conversation, inbox_id = conversation.inbox_id)
    KanbanBoard.accepting_inbox_for_account(conversation.account_id, inbox_id)
               .where('kanban_boards.won_recurrence_enabled OR kanban_boards.lost_recurrence_enabled')
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
