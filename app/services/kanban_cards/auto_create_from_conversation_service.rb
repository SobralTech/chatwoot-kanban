class KanbanCards::AutoCreateFromConversationService
  def initialize(conversation, kanban_board: nil, inbox: nil, recreated_from_card_id: nil)
    @conversation = conversation
    @kanban_board = kanban_board
    @provided_inbox = inbox
    @recreated_from_card_id = recreated_from_card_id
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

  attr_reader :conversation, :kanban_board, :provided_inbox, :recreated_from_card_id, :summary

  def eligible_boards
    return targeted_board if kanban_board.present?

    boards = KanbanBoard.active
                        .where(account_id: conversation.account_id, auto_create_cards_from_conversations: true)
                        .accepting_inbox(inbox.id)

    boards.where.not(id: boards_with_terminal_history_ids)
  end

  def targeted_board
    KanbanBoard.active
               .where(account_id: conversation.account_id, id: kanban_board.id)
               .accepting_inbox(inbox.id)
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
    dispatch_card_created_event(card) if card.present?
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
      lock_active_cards!(kanban_board, stage)
      shift_active_cards_down!(kanban_board, stage)
      card = create_card!(kanban_board, stage)
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
      position: 1,
      active: true,
      recreated_from_card_id: recreated_from_card_id
    )
  end

  def dispatch_card_created_event(card)
    Rails.configuration.dispatcher.dispatch(
      Events::Types::KANBAN_CARD_CREATED,
      Time.zone.now,
      account_id: card.account_id,
      board_id: card.kanban_board_id,
      stage_id: card.kanban_stage_id,
      card_id: card.id,
      conversation_id: card.conversation_id
    )
  end

  def lock_active_cards!(kanban_board, stage)
    KanbanCard.lock_active_cards_for_stages!(kanban_board, [stage.id])
  end

  def shift_active_cards_down!(kanban_board, stage)
    KanbanCard.where(kanban_board: kanban_board, kanban_stage: stage).active.update_all( # rubocop:disable Rails/SkipsModelValidations
      ['position = position + 1, updated_at = ?', Time.current]
    )
  end

  def automatic_card_exists?(kanban_board)
    return KanbanCard.conversation.exists?(kanban_board: kanban_board, conversation_id: conversation.id) if recreated_from_card_id.blank?

    KanbanCard.active.where(kanban_board: kanban_board, contact_id: contact.id)
              .where.not(kanban_stage_id: terminal_stage_ids(kanban_board))
              .exists?
  end

  def boards_with_terminal_history_ids
    KanbanCard.joins(:kanban_board)
              .where(kanban_cards: { account_id: conversation.account_id, contact_id: contact.id })
              .where(<<~SQL.squish)
                kanban_cards.kanban_stage_id = kanban_boards.won_stage_id OR
                kanban_cards.kanban_stage_id = kanban_boards.lost_stage_id
              SQL
              .distinct
              .pluck(:kanban_board_id)
  end

  def terminal_stage_ids(board)
    [board.won_stage_id, board.lost_stage_id].compact.uniq
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
