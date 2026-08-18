class KanbanCards::RecordEventService
  def self.call(card:, event_type:, user: nil, metadata: {}, created_at: Time.current)
    KanbanCardEvent.create!(
      **scope_attributes(card, user, created_at),
      kanban_card_id: card.id,
      event_type: event_type,
      metadata: metadata
    )
  end

  # The card row is already gone when this runs, so the event is board scoped and
  # keeps the card id in the metadata.
  def self.card_deleted(card:, user: nil, metadata: {})
    KanbanCardEvent.create!(
      **scope_attributes(card, user, Time.current),
      kanban_card_id: nil,
      event_type: 'card_deleted',
      metadata: metadata.merge(card_id: card.id)
    )
  end

  def self.scope_attributes(card, user, created_at)
    {
      account_id: card.account_id,
      kanban_board_id: card.kanban_board_id,
      user_id: user&.id,
      created_at: created_at
    }
  end
  private_class_method :scope_attributes
end
