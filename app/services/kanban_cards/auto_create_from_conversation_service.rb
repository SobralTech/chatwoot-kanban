class KanbanCards::AutoCreateFromConversationService
  def initialize(conversation, kanban_board: nil, inbox: nil, recreated_from_card_id: nil, context: {})
    @conversation = conversation
    @kanban_board = kanban_board
    @provided_inbox = inbox
    @recreated_from_card_id = recreated_from_card_id
    @context = context.to_h.with_indifferent_access
    @summary = summary_hash
  end

  def perform!
    return summary unless contact && inbox

    eligible_boards.find_each do |kanban_board|
      create_for_board(kanban_board)
    end

    summary
  end

  private

  attr_reader :conversation, :kanban_board, :provided_inbox, :recreated_from_card_id, :summary, :context

  def eligible_boards
    scope = KanbanBoard.accepting_inbox_for_account(conversation.account_id, inbox.id)
    return scope.where(id: kanban_board.id) if kanban_board.present?

    scope.where(auto_create_cards_from_conversations: true).where.not(id: boards_with_terminal_history_ids)
  end

  def create_for_board(kanban_board)
    card = KanbanCard.transaction do
      stage = first_active_stage(kanban_board)
      if stage.blank?
        skip_without_active_stage
        nil
      else
        stage.lock!
        create_for_stage(kanban_board, stage)
      end
    end
    if card.present?
      dispatch_card_created_event(card)
      trigger_automation(card)
    end
  rescue ActiveRecord::RecordNotUnique
    skip_existing_card
  end

  def first_active_stage(kanban_board)
    kanban_board.kanban_stages.active.ordered.first
  end

  def create_for_stage(kanban_board, stage)
    if automatic_card_exists?(kanban_board)
      skip_existing_card
      nil
    else
      card = create_card!(kanban_board, stage)
      KanbanCards::RecordEventService.card_created(card)
      summary[:created] += 1
      card
    end
  end

  def create_card!(kanban_board, stage)
    KanbanCard.create!(
      account_id: conversation.account_id,
      kanban_board: kanban_board,
      kanban_stage: stage,
      contact: contact,
      inbox: inbox,
      conversation: conversation,
      subject: default_subject,
      origin: 'conversation',
      position: KanbanCard.top_position(kanban_board: kanban_board, kanban_stage: stage),
      active: true,
      recreated_from_card_id: recreated_from_card_id
    )
  end

  def dispatch_card_created_event(card)
    KanbanCards::EventDispatcher.card_event(Events::Types::KANBAN_CARD_CREATED, card)
  end

  def trigger_automation(card)
    KanbanAutomations::TriggerService.call(card: card, event_name: 'card_created', user: nil, context: context)
  end

  def automatic_card_exists?(kanban_board)
    return KanbanCard.conversation.exists?(kanban_board: kanban_board, conversation_id: conversation.id) if recreated_from_card_id.blank?

    KanbanCard.active_non_terminal_for(kanban_board, contact.id).exists?
  end

  def boards_with_terminal_history_ids
    latest_terminal_cards_per_board.select do |row|
      (row.kanban_stage_id == row.won_stage_id && row.won_recurrence_enabled) ||
        (row.kanban_stage_id == row.lost_stage_id && row.lost_recurrence_enabled)
    end.map(&:kanban_board_id)
  end

  def latest_terminal_cards_per_board
    KanbanCard.joins(:kanban_board)
              .where(kanban_cards: { account_id: conversation.account_id, contact_id: contact.id })
              .where('kanban_cards.kanban_stage_id IN (kanban_boards.won_stage_id, kanban_boards.lost_stage_id)')
              .select(
                'DISTINCT ON (kanban_cards.kanban_board_id) kanban_cards.kanban_board_id, ' \
                'kanban_cards.kanban_stage_id, kanban_boards.won_stage_id, kanban_boards.won_recurrence_enabled, ' \
                'kanban_boards.lost_stage_id, kanban_boards.lost_recurrence_enabled'
              )
              .order('kanban_cards.kanban_board_id, kanban_cards.stage_entered_at DESC, kanban_cards.id DESC')
  end

  def default_subject
    "#{contact_display_name} - #{inbox_display_name}"
  end

  def contact_display_name
    contact.name.presence || "Contact ##{contact.id}"
  end

  def inbox_display_name
    inbox.name.presence || "Inbox ##{inbox.id}"
  end

  def contact
    @contact ||= conversation.contact
  end

  def inbox
    @inbox ||= provided_inbox || conversation.inbox
  end

  def skip_existing_card
    summary[:skipped][:existing_card] += 1
  end

  def skip_without_active_stage
    summary[:skipped][:without_active_stage] += 1
  end

  def summary_hash
    {
      created: 0,
      skipped: {
        existing_card: 0,
        without_active_stage: 0
      }
    }
  end
end
