# The card-level ActionCable payloads, in one place. The board-level events (a whole
# stage reordered or deleted) keep their own shape and stay with the stage controller.
class KanbanCards::EventDispatcher
  def self.card_event(event_name, card, board_id: nil, stage_id: nil)
    dispatch(
      event_name,
      account_id: card.account_id,
      board_id: board_id || card.kanban_board_id,
      stage_id: stage_id || card.kanban_stage_id,
      card_id: card.id,
      conversation_id: card.conversation_id
    )
  end

  def self.card_reordered(card, source_stage_id:)
    dispatch(
      Events::Types::KANBAN_CARD_REORDERED,
      account_id: card.account_id,
      board_id: card.kanban_board_id,
      card_id: card.id,
      conversation_id: card.conversation_id,
      source_stage_id: source_stage_id,
      target_stage_id: card.kanban_stage_id
    )
  end

  def self.dispatch(event_name, **payload)
    Rails.configuration.dispatcher.dispatch(event_name, Time.zone.now, **payload)
  end
  private_class_method :dispatch
end
