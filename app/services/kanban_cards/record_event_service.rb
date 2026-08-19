class KanbanCards::RecordEventService
  def self.call(card:, event_type:, user: nil, metadata: {}, created_at: Time.current)
    KanbanCardEvent.create!(
      **scope_attributes(card, user, created_at),
      kanban_card_id: card.id,
      event_type: event_type,
      metadata: metadata
    )
  end

  def self.card_created(card, user: nil, created_at: Time.current)
    call(
      card: card,
      event_type: 'card_created',
      user: user,
      metadata: card_created_metadata(card.attributes),
      created_at: created_at
    )
  end

  # Shared with the bulk import, which builds its rows straight from the INSERT
  # ... RETURNING result instead of loading records.
  def self.card_created_metadata(attributes)
    {
      origin: attributes['origin'],
      stage_id: attributes['kanban_stage_id'],
      conversation_id: attributes['conversation_id'],
      recreated_from_card_id: attributes['recreated_from_card_id']
    }
  end

  def self.labels_changed(card:, from:, to:, user: nil)
    diff_event(card, 'labels_changed', { added: to - from, removed: from - to }, user)
  end

  def self.assignees_changed(card:, from:, to:, user: nil)
    diff_event(card, 'assignees_changed', { added_ids: to - from, removed_ids: from - to }, user)
  end

  def self.attribute_changed(card:, event_type:, from:, to:, user: nil)
    return if from == to

    call(card: card, event_type: event_type, user: user, metadata: { from: serialize(from), to: serialize(to) })
  end

  # Timestamps go into the metadata as ISO8601 so the timeline renders them without
  # having to know which attribute it is looking at.
  def self.serialize(value)
    value.respond_to?(:iso8601) ? value.iso8601 : value
  end
  private_class_method :serialize

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

  def self.diff_event(card, event_type, diff, user)
    return if diff.values.all?(&:blank?)

    call(card: card, event_type: event_type, user: user, metadata: diff.transform_values(&:sort))
  end
  private_class_method :diff_event

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
