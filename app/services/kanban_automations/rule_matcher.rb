# Decides whether a card satisfies every condition a rule carries. Two tables say all of
# it: what each attribute reads off the card, and what each operator compares. Anything
# the tables do not know -- an attribute or operator that is not in the vocabulary -- is
# a condition that cannot be satisfied, so the rule does not fire.
class KanbanAutomations::RuleMatcher
  NUMERIC_ATTRIBUTES = %w[stage_id previous_stage_id inbox_id assignee_id reason_id total_value hours_in_stage].freeze

  ATTRIBUTES = {
    'stage_id' => ->(card) { card.kanban_stage_id },
    'previous_stage_id' => ->(card) { card.previous_stage_id },
    'priority' => ->(card) { card.priority },
    'labels' => ->(card) { card.label_list.to_a },
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

  # `self` inside these is the class, so they read as plain calls to the coercions below.
  OPERATORS = {
    'equal_to' => ->(value, values, key) { equal_to?(value, values.first, key) },
    'not_equal_to' => ->(value, values, key) { !equal_to?(value, values.first, key) },
    'is_present' => ->(value, _values, _key) { value.present? },
    'is_not_present' => ->(value, _values, _key) { value.blank? },
    'greater_than' => ->(value, values, _key) { numeric_compare(value, values.first, :>) },
    'less_than' => ->(value, values, _key) { numeric_compare(value, values.first, :<) },
    'is_one_of' => ->(value, values, key) { values.any? { |expected| equal_to?(value, expected, key) } },
    'includes' => ->(value, values, key) { includes?(value, values, key) }
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

    operator.call(attribute.call(card), Array(condition[:values]), attribute_key)
  end

  class << self
    private

    def equal_to?(value, expected, attribute_key)
      return value.any? { |item| scalar_equal?(item, expected, attribute_key) } if value.is_a?(Array)

      scalar_equal?(value, expected, attribute_key)
    end

    def scalar_equal?(value, expected, attribute_key)
      return false if value.nil? || expected.nil?

      if boolean_value?(value) || boolean_value?(expected)
        ActiveModel::Type::Boolean.new.cast(value) == ActiveModel::Type::Boolean.new.cast(expected)
      elsif NUMERIC_ATTRIBUTES.include?(attribute_key)
        numeric_compare(value, expected, :==)
      else
        value.to_s == expected.to_s
      end
    end

    def includes?(value, expected_values, attribute_key)
      return expected_values.any? { |expected| value.to_s.include?(expected.to_s) } unless value.is_a?(Array)

      expected_values.any? { |expected| value.any? { |item| scalar_equal?(item, expected, attribute_key) } }
    end

    # Ordering only means something between two numbers: a blank total, or a value typed
    # as text, is a condition that does not match rather than an exception.
    def numeric_compare(value, expected, operator)
      left = numeric_value(value)
      right = numeric_value(expected)
      return false if left.nil? || right.nil?

      left.public_send(operator, right)
    end

    def numeric_value(value)
      BigDecimal(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def boolean_value?(value)
      value == true || value == false || %w[true false].include?(value.to_s.downcase)
    end
  end
end
