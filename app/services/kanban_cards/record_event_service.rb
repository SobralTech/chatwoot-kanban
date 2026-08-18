class KanbanCards::RecordEventService
  def self.call(card:, event_type:, user: nil, metadata: {}, created_at: Time.current)
    KanbanCardEvent.create!(
      account_id: card.account_id,
      kanban_card_id: card.id,
      kanban_board_id: card.kanban_board_id,
      user_id: user&.id,
      event_type: event_type,
      metadata: metadata,
      created_at: created_at
    )
  end
end
