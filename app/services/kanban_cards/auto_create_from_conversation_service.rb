class KanbanCards::AutoCreateFromConversationService
  def initialize(conversation)
    @conversation = conversation
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

  attr_reader :conversation, :summary

  def eligible_boards
    KanbanBoard.active
               .where(account_id: conversation.account_id, auto_create_cards_from_conversations: true)
               .accepting_inbox(conversation.inbox_id)
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
      active: true
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
    KanbanCard.conversation.exists?(kanban_board: kanban_board, conversation_id: conversation.id)
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
    @inbox ||= conversation.inbox
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
