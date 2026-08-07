class KanbanCards::EvaluateContactRecurrenceService
  def initialize(conversation:, kanban_board:, inbox: nil)
    @conversation = conversation
    @kanban_board = kanban_board
    @inbox = inbox || conversation&.inbox
  end

  def perform!
    return unless valid_context?

    KanbanCard.transaction do
      reference_card = latest_terminal_card
      next if reference_card.blank?

      window_hours = kanban_board.recurrence_window_hours_for(reference_card.kanban_stage_id)
      next if window_hours.blank?
      next unless Time.current - reference_card.stage_entered_at >= window_hours.hours
      next if active_pipeline_card_exists?

      KanbanCards::AutoCreateFromConversationService.new(
        conversation,
        kanban_board: kanban_board,
        inbox: inbox,
        recreated_from_card_id: reference_card.id
      ).perform!
    end
  end

  private

  attr_reader :conversation, :kanban_board, :inbox

  def valid_context?
    conversation.present? && kanban_board.present? && inbox.present? &&
      valid_conversation_context? && valid_inbox_context?
  end

  def valid_conversation_context?
    conversation.contact.present? && kanban_board.active? && conversation.account_id == kanban_board.account_id
  end

  def valid_inbox_context?
    inbox.account_id == conversation.account_id && kanban_board.inbox_allowed?(inbox)
  end

  def latest_terminal_card
    terminal_cards.order(stage_entered_at: :desc, id: :desc).lock.first
  end

  def terminal_cards
    KanbanCard.where(
      account_id: conversation.account_id,
      kanban_board_id: kanban_board.id,
      contact_id: conversation.contact_id,
      kanban_stage_id: KanbanStage.special_stage_ids(kanban_board)
    )
  end

  def active_pipeline_card_exists?
    KanbanCard.active_non_terminal_for(kanban_board, conversation.contact_id).exists?
  end
end
