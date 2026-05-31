class KanbanCards::SyncConversationStateService
  def initialize(state)
    @state = state
  end

  def sync!
    card = mirrored_card || KanbanCard.new
    apply_mirrored_attributes(card)
    card.save!
    card
  rescue ActiveRecord::RecordNotUnique
    card = mirrored_card
    apply_mirrored_attributes(card)
    card.save!
    card
  end

  def deactivate!
    mirrored_card&.update!(active: false)
  end

  private

  attr_reader :state

  def mirrored_card
    KanbanCard.conversation
              .where(kanban_board_id: state.kanban_board_id, conversation_id: state.conversation_id)
              .order(active: :desc, id: :asc)
              .first
  end

  def apply_mirrored_attributes(card)
    card.assign_attributes(mirrored_attributes)
  end

  def mirrored_attributes
    {
      account_id: state.conversation.account_id,
      kanban_board_id: state.kanban_board_id,
      kanban_stage_id: state.kanban_stage_id,
      contact_id: state.conversation.contact_id,
      inbox_id: state.conversation.inbox_id,
      conversation_id: state.conversation_id,
      subject: nil,
      normalized_subject: nil,
      origin: 'conversation',
      position: state.position,
      active: true
    }
  end
end
