class KanbanCards::RecordEventService
  def self.call(card:, event_type:, user: nil, metadata: {}, created_at: Time.current)
    KanbanCardEvent.create!(
      **scope_attributes(card, user, created_at),
      kanban_card: card,
      event_type: event_type,
      metadata: metadata.merge(automation_metadata)
    )
  end

  def self.card_created(card, user: nil, created_at: Time.current, entry_rule: nil)
    call(
      card: card,
      event_type: 'card_created',
      user: user,
      metadata: card_created_metadata(card.attributes).merge(entry_rule_metadata(entry_rule)),
      created_at: created_at
    )
  end

  # Names the entry rule that let the conversation in, so a card that appeared on its own
  # can say which rule put it there.
  def self.entry_rule_metadata(entry_rule)
    return {} if entry_rule.blank?

    { entry_rule_id: entry_rule.id, entry_rule_name: entry_rule.name }
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

    call(
      card: card,
      event_type: event_type,
      user: user,
      metadata: { from: serialize(from), to: serialize(to) }
    )
  end

  def self.automation_action(card:, action_name:, status:, metadata: {})
    call(
      card: card,
      event_type: 'automation_action',
      user: nil,
      metadata: { action_name: action_name, status: status }.merge(metadata)
    )
  end

  # An automation run marks itself on Current the same way AutomationRules::ActionService
  # does, so every event it records is stamped here instead of each caller threading the
  # rule id down through the card services.
  def self.automation_metadata
    rule = Current.executed_by
    return {} unless rule.is_a?(KanbanAutomationRule)

    { automation_rule_id: rule.id }
  end
  private_class_method :automation_metadata

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
      metadata: metadata.merge(card_id: card.id).merge(automation_metadata)
    )
  end

  def self.diff_event(card, event_type, diff, user)
    return if diff.values.all?(&:blank?)

    call(card: card, event_type: event_type, user: user, metadata: diff.transform_values(&:sort))
  end
  private_class_method :diff_event

  def self.scope_attributes(card, user, created_at)
    {
      account: card.account,
      kanban_board: card.kanban_board,
      user: user,
      created_at: created_at
    }
  end
  private_class_method :scope_attributes
end
