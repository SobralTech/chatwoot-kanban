class KanbanAutomations::RuleMatcher
  NUMERIC_ATTRIBUTES = %w[stage_id previous_stage_id inbox_id assignee_id reason_id total_value hours_in_stage].freeze
  ATTRIBUTE_VALUE_METHODS = {
    'stage_id' => :stage_id_value,
    'previous_stage_id' => :previous_stage_id_value,
    'priority' => :priority_value,
    'labels' => :labels_value,
    'assignee_id' => :assignee_ids_value,
    'inbox_id' => :inbox_id_value,
    'total_value' => :total_value,
    'hours_in_stage' => :hours_in_stage,
    'reason_id' => :reason_id_value,
    'origin' => :origin_value,
    'contact_has_open_card' => :contact_has_open_card?
  }.freeze
  OPERATOR_METHODS = {
    'equal_to' => :equal_to_condition,
    'not_equal_to' => :not_equal_to_condition,
    'is_present' => :present_condition,
    'is_not_present' => :not_present_condition,
    'greater_than' => :greater_than_condition,
    'less_than' => :less_than_condition,
    'is_one_of' => :one_of_condition,
    'includes' => :includes_condition
  }.freeze

  def self.match?(card, rule)
    new(card, rule).match?
  end

  def initialize(card, rule)
    @card = card
    @rule = rule
  end

  def match?
    Array(rule.conditions).all? { |condition| condition_matches?(condition.with_indifferent_access) }
  rescue StandardError => e
    Rails.logger.error("Kanban automation matcher failed for rule #{rule.id}: #{e.message}")
    false
  end

  private

  attr_reader :card, :rule

  def condition_matches?(condition)
    value = attribute_value(condition[:attribute_key])
    values = Array(condition[:values])
    method_name = OPERATOR_METHODS[condition[:filter_operator].to_s]
    return false unless method_name

    send(method_name, value, values, condition[:attribute_key].to_s)
  rescue ArgumentError, TypeError
    false
  end

  def attribute_value(attribute_key)
    method_name = ATTRIBUTE_VALUE_METHODS[attribute_key.to_s]
    method_name ? send(method_name) : nil
  end

  def stage_id_value
    card.kanban_stage_id
  end

  def previous_stage_id_value
    card.previous_stage_id
  end

  def priority_value
    card.priority
  end

  def labels_value
    card.label_list.to_a
  end

  def assignee_ids_value
    card.kanban_card_assignees.pluck(:user_id)
  end

  def inbox_id_value
    card.inbox_id
  end

  def total_value
    card.total_value
  end

  def hours_in_stage
    (Time.current - card.stage_entered_at) / 1.hour
  end

  def reason_id_value
    card.kanban_reason_id
  end

  def origin_value
    card.origin
  end

  def contact_has_open_card?
    KanbanCard.active_non_terminal_for(card.kanban_board, card.contact_id).where.not(id: card.id).exists?
  end

  def equal_to_condition(value, values, attribute_key)
    equal_to?(value, values.first, attribute_key)
  end

  def not_equal_to_condition(value, values, attribute_key)
    !equal_to?(value, values.first, attribute_key)
  end

  def present_condition(value, _values, _attribute_key)
    value.present?
  end

  def not_present_condition(value, _values, _attribute_key)
    value.blank?
  end

  def greater_than_condition(value, values, _attribute_key)
    numeric_value(value) > numeric_value(values.first)
  end

  def less_than_condition(value, values, _attribute_key)
    numeric_value(value) < numeric_value(values.first)
  end

  def one_of_condition(value, values, attribute_key)
    values.any? { |expected| equal_to?(value, expected, attribute_key) }
  end

  def includes_condition(value, values, attribute_key)
    includes?(value, values, attribute_key)
  end

  def equal_to?(value, expected, attribute_key)
    return value.any? { |item| scalar_equal?(item, expected, attribute_key) } if value.is_a?(Array)

    scalar_equal?(value, expected, attribute_key)
  end

  def scalar_equal?(value, expected, attribute_key)
    return false if value.nil? || expected.nil?

    if boolean_value?(value) || boolean_value?(expected)
      ActiveModel::Type::Boolean.new.cast(value) == ActiveModel::Type::Boolean.new.cast(expected)
    elsif NUMERIC_ATTRIBUTES.include?(attribute_key)
      numeric_value(value) == numeric_value(expected)
    else
      value.to_s == expected.to_s
    end
  end

  def includes?(value, expected_values, attribute_key)
    if value.is_a?(Array)
      expected_values.any? { |expected| value.any? { |item| scalar_equal?(item, expected, attribute_key) } }
    else
      expected_values.any? { |expected| value.to_s.include?(expected.to_s) }
    end
  end

  def numeric_value(value)
    BigDecimal(value.to_s)
  end

  def boolean_value?(value)
    value == true || value == false || %w[true false].include?(value.to_s.downcase)
  end
end
