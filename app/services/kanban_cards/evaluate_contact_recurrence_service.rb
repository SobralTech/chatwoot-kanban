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
      next if active_pipeline_card_exists?
      next unless recurrence_enabled_for?(reference_card)
      next unless outside_recurrence_window?(reference_card)

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
      kanban_stage_id: terminal_stage_ids
    )
  end

  def terminal_stage_ids
    @terminal_stage_ids ||= [kanban_board.won_stage_id, kanban_board.lost_stage_id].compact.uniq
  end

  def active_pipeline_card_exists?
    cards = KanbanCard.active.where(
      account_id: conversation.account_id,
      kanban_board_id: kanban_board.id,
      contact_id: conversation.contact_id
    )

    cards.where.not(kanban_stage_id: terminal_stage_ids).exists?
  end

  def recurrence_enabled_for?(reference_card)
    if reference_card.kanban_stage_id == kanban_board.won_stage_id
      kanban_board.won_recurrence_enabled? && kanban_board.won_recurrence_window_hours.present?
    else
      kanban_board.lost_recurrence_enabled? && kanban_board.lost_recurrence_window_hours.present?
    end
  end

  def outside_recurrence_window?(reference_card)
    window_hours = if reference_card.kanban_stage_id == kanban_board.won_stage_id
                     kanban_board.won_recurrence_window_hours
                   else
                     kanban_board.lost_recurrence_window_hours
                   end

    Time.current - reference_card.stage_entered_at >= window_hours.hours
  end
end
