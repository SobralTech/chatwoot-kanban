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
               .where(account_id: conversation.account_id, auto_create_cards_from_conversations: true, use_opportunity_card_reads: true)
  end

  def create_for_board(kanban_board)
    KanbanCard.transaction do
      default_stage = kanban_board.default_stage
      if default_stage.blank?
        skip_invalid_default_stage
      else
        default_stage.lock!
        create_for_active_stage(kanban_board, default_stage)
      end
    end
  rescue ActiveRecord::RecordNotUnique
    skip_existing_card
  end

  def create_for_active_stage(kanban_board, default_stage)
    if !default_stage.active?
      skip_invalid_default_stage
    elsif automatic_card_exists?(kanban_board)
      skip_existing_card
    else
      create_card!(kanban_board, default_stage)
      summary[:created] += 1
    end
  end

  def create_card!(kanban_board, default_stage)
    KanbanCard.create!(
      account_id: conversation.account_id,
      kanban_board: kanban_board,
      kanban_stage: default_stage,
      contact: contact,
      inbox: inbox,
      conversation: conversation,
      subject: default_subject,
      normalized_subject: nil,
      origin: 'conversation',
      position: next_position(kanban_board, default_stage),
      active: true
    )
  end

  def automatic_card_exists?(kanban_board)
    KanbanCard.conversation.exists?(kanban_board: kanban_board, conversation_id: conversation.id)
  end

  def next_position(kanban_board, default_stage)
    kanban_board.kanban_cards.active.where(kanban_stage: default_stage).maximum(:position).to_i + 1
  end

  def default_subject
    "Lead [#{contact_display_name}] - [#{inbox_display_name}]"
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

  def skip_invalid_default_stage
    summary[:skipped][:invalid_default_stage] += 1
  end

  def summary_hash
    {
      created: 0,
      skipped: {
        existing_card: 0,
        invalid_default_stage: 0
      }
    }
  end
end
