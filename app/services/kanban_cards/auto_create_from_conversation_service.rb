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

    eligible_boards.find_each do |board|
      # The recurrence path names its board, and by then the decision to bring the contact
      # back has already been made -- re-reading the entry rules there would reject the
      # return precisely because the old conversation was closed and cleaned up.
      rule = kanban_board.present? ? nil : matching_rule(board)
      next if kanban_board.blank? && rule.blank?

      create_for_board(board, rule)
    end

    summary
  end

  private

  attr_reader :conversation, :kanban_board, :provided_inbox, :recreated_from_card_id, :summary, :context

  def eligible_boards
    scope = KanbanBoard.accepting_inbox_for_account(conversation.account_id, inbox.id)
    return scope.where(id: kanban_board.id) if kanban_board.present?

    scope.where.not(id: boards_with_terminal_history_ids)
  end

  # The rule that admits this conversation: the first active one, by position, whose
  # inboxes cover it and whose conditions it satisfies. Only that one is used, so a
  # conversation matching several rules still gets a single card.
  def matching_rule(board)
    board.kanban_board_entry_rules.active.ordered.includes(:kanban_board_entry_rule_inboxes).find do |rule|
      rule_accepts_inbox?(rule) && KanbanBoardEntryRules::Matcher.match?(conversation, rule)
    end
  end

  def rule_accepts_inbox?(rule)
    rule.all_inboxes? || rule.kanban_board_entry_rule_inboxes.any? { |join| join.inbox_id == inbox.id }
  end

  def create_for_board(kanban_board, rule)
    return skip_existing_card if automatic_card_exists?(kanban_board)

    card = KanbanCard.transaction do
      stage = stage_for(kanban_board, rule)
      if stage.blank?
        skip_without_active_stage
        nil
      else
        stage.lock!
        create_for_stage(kanban_board, stage, rule)
      end
    end
    if card.present?
      dispatch_card_created_event(card)
      trigger_automation(card)
    end
  rescue ActiveRecord::RecordNotUnique
    skip_existing_card
  end

  # A rule may name its landing stage. If that stage was archived after the rule was
  # written, the card falls back to the first active stage rather than not being created.
  def stage_for(kanban_board, rule)
    configured = rule&.kanban_stage
    return configured if configured&.active? && configured.kanban_board_id == kanban_board.id

    first_active_stage(kanban_board)
  end

  def first_active_stage(kanban_board)
    kanban_board.kanban_stages.active.ordered.first
  end

  def create_for_stage(kanban_board, stage, rule)
    if automatic_card_exists?(kanban_board)
      skip_existing_card
      nil
    else
      card = create_card!(kanban_board, stage)
      # Only matches are recorded, and on the card's own trail: rejections are close to
      # the account's whole conversation traffic, so a log of them would bury the answer
      # it was meant to give. "Why did this one not come in?" is the preview's job.
      KanbanCards::RecordEventService.card_created(card, entry_rule: rule)
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
    KanbanCard.default_subject_for(contact: contact, inbox: inbox)
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
