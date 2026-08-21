# Every KANBAN_CARD_* ActionCable payload, in one place. A card-level event names the
# card that moved; a stage-level one names only the stage, because it stands for all of
# the cards in it at once.
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

  def self.stage_cards_reordered(board, source_stage_id:, target_stage_id:)
    dispatch(
      Events::Types::KANBAN_CARD_REORDERED,
      account_id: board.account_id,
      board_id: board.id,
      source_stage_id: source_stage_id,
      target_stage_id: target_stage_id
    )
  end

  def self.stage_cards_deleted(board, stage_id:)
    dispatch(
      Events::Types::KANBAN_CARD_DELETED,
      account_id: board.account_id,
      board_id: board.id,
      stage_id: stage_id
    )
  end

  def self.dispatch(event_name, **payload)
    Rails.configuration.dispatcher.dispatch(event_name, Time.zone.now, **payload)
  end
  private_class_method :dispatch
end
