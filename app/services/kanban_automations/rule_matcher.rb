# Decides whether a card satisfies every condition a rule carries. Two tables say all of
# it: what each attribute reads off the card, and what each operator compares. Anything
# the tables do not know -- an attribute or operator that is not in the vocabulary -- is
# a condition that cannot be satisfied, so the rule does not fire.
class KanbanAutomations::RuleMatcher
  extend KanbanConditions::Coercions

  NUMERIC_ATTRIBUTES = %w[stage_id previous_stage_id inbox_id assignee_id reason_id total_value hours_in_stage].freeze

  ATTRIBUTES = {
    'stage_id' => ->(card) { card.kanban_stage_id },
    'previous_stage_id' => ->(card) { card.previous_stage_id },
    'priority' => ->(card) { card.priority },
    # `labels` is the tag association behind label_list, and unlike label_list it can be
    # preloaded -- which the preview, matching a page of cards at once, depends on.
    'labels' => ->(card) { card.labels.map(&:name) },
    'assignee_id' => ->(card) { card.kanban_card_assignees.map(&:user_id) },
    'inbox_id' => ->(card) { card.inbox_id },
    'total_value' => ->(card) { card.total_value },
    'hours_in_stage' => ->(card) { (Time.current - card.stage_entered_at) / 1.hour },
    'reason_id' => ->(card) { card.kanban_reason_id },
    'origin' => ->(card) { card.origin },
    'contact_has_open_card' => lambda { |card|
      KanbanCard.active_non_terminal_for(card.kanban_board, card.contact_id).where.not(id: card.id).exists?
    }
  }.freeze

  # `self` inside these is the class, so they read as plain calls to the coercions the
  # class extends.
  OPERATORS = {
    'equal_to' => ->(value, values, numeric) { equal_to?(value, values.first, numeric: numeric) },
    'not_equal_to' => ->(value, values, numeric) { !equal_to?(value, values.first, numeric: numeric) },
    'is_present' => ->(value, _values, _numeric) { value.present? },
    'is_not_present' => ->(value, _values, _numeric) { value.blank? },
    'greater_than' => ->(value, values, _numeric) { numeric_compare(value, values.first, :>) },
    'less_than' => ->(value, values, _numeric) { numeric_compare(value, values.first, :<) },
    'is_one_of' => ->(value, values, numeric) { values.any? { |expected| equal_to?(value, expected, numeric: numeric) } },
    'includes' => ->(value, values, numeric) { includes?(value, values, numeric: numeric) }
  }.freeze

  def self.match?(card, rule)
    new(card, rule).match?
  end

  def initialize(card, rule)
    @card = card
    @rule = rule
  end

  # A rule without conditions matches every card it is handed: the event is the condition.
  def match?
    Array(rule.conditions).all? { |condition| condition_matches?(condition.with_indifferent_access) }
  end

  private

  attr_reader :card, :rule

  def condition_matches?(condition)
    attribute_key = condition[:attribute_key].to_s
    attribute = ATTRIBUTES[attribute_key]
    operator = OPERATORS[condition[:filter_operator].to_s]
    return false unless attribute && operator

    operator.call(attribute.call(card), Array(condition[:values]), NUMERIC_ATTRIBUTES.include?(attribute_key))
  end
end
