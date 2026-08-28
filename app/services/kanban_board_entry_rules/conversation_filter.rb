# Applies entry-rule conditions to a Conversation relation. Returning nil means a
# condition is not supported in SQL yet and the caller must use the Ruby matcher.
class KanbanBoardEntryRules::ConversationFilter
  extend KanbanConditions::Coercions

  UNSUPPORTED = Object.new.freeze
  FALSE_PREDICATE = Arel.sql('FALSE')
  TRUE_PREDICATE = Arel.sql('TRUE')
  CONVERSATIONS = Conversation.arel_table

  def self.apply(relation, rule)
    new(rule).apply(relation)
  end

  def initialize(rule)
    @conditions = Array(rule&.conditions).map(&:with_indifferent_access)
  end

  def apply(relation)
    predicates = conditions.map { |condition| condition_predicate(condition) }
    return if predicates.include?(UNSUPPORTED)

    predicates.reduce(relation) { |scope, predicate| scope.where(predicate) }
  end

  private

  attr_reader :conditions

  def condition_predicate(condition)
    attribute_key = condition[:attribute_key].to_s
    operator = condition[:filter_operator].to_s
    return UNSUPPORTED unless KanbanBoardEntryRule::OPERATORS_BY_ATTRIBUTE.fetch(attribute_key, []).include?(operator)

    case attribute_key
    when 'labels'
      labels_predicate(operator, Array(condition[:values]))
    when 'assignee_id', 'team_id'
      scalar_predicate(attribute_key, operator, Array(condition[:values]), method(:numeric_condition_value))
    when 'priority'
      scalar_predicate(attribute_key, operator, Array(condition[:values]), method(:priority_condition_value))
    else
      UNSUPPORTED
    end
  end

  def labels_predicate(operator, expected_values)
    predicates = expected_values.map { |value| label_predicate(value) }

    case operator
    when 'includes_any'
      boolean_predicate(any_predicate(predicates))
    when 'includes_all'
      boolean_predicate(all_predicate(predicates))
    when 'not_includes'
      negate(boolean_predicate(any_predicate(predicates)))
    else
      UNSUPPORTED
    end
  end

  def label_predicate(value)
    return no_value_predicate(CONVERSATIONS[:cached_label_list]) if none_value?(value)
    return FALSE_PREDICATE if value.nil?

    Arel::Nodes::InfixOperation.new(
      '=',
      Arel::Nodes.build_quoted(value.to_s),
      Arel::Nodes::NamedFunction.new('ANY', [label_array_expression])
    )
  end

  def label_array_expression
    value = Arel::Nodes::NamedFunction.new(
      'COALESCE',
      [CONVERSATIONS[:cached_label_list], Arel::Nodes.build_quoted('')]
    )
    trimmed = Arel::Nodes::NamedFunction.new('BTRIM', [value])

    Arel::Nodes::NamedFunction.new(
      'REGEXP_SPLIT_TO_ARRAY',
      [trimmed, Arel::Nodes.build_quoted('\\s*,\\s*')]
    )
  end

  def scalar_predicate(attribute_key, operator, expected_values, coercion)
    column = CONVERSATIONS[attribute_key]
    include_none = expected_values.any? { |value| none_value?(value) }
    values = expected_values.filter_map do |value|
      next if value.nil? || none_value?(value)

      coercion.call(value)
    end.uniq
    match = scalar_match_predicate(column, values, include_none)

    case operator
    when 'is_one_of'
      match
    when 'is_not_one_of'
      negate(match)
    else
      UNSUPPORTED
    end
  end

  def scalar_match_predicate(column, values, include_none)
    predicates = []
    predicates << column.in(values) if values.present?
    predicates << column.eq(nil) if include_none
    boolean_predicate(any_predicate(predicates))
  end

  def numeric_condition_value(value)
    number = self.class.numeric_value(value)
    number.to_i if number&.frac&.zero?
  end

  def priority_condition_value(value)
    Conversation.priorities[value.to_s]
  end

  def none_value?(value)
    value.to_s == KanbanBoardEntryRule::NONE_VALUE
  end

  def no_value_predicate(column)
    column.eq(nil).or(column.eq(''))
  end

  def any_predicate(predicates)
    return FALSE_PREDICATE if predicates.empty?

    predicates.reduce { |combined, predicate| combined.or(predicate) }
  end

  def all_predicate(predicates)
    return TRUE_PREDICATE if predicates.empty?

    predicates.reduce { |combined, predicate| combined.and(predicate) }
  end

  def boolean_predicate(predicate)
    Arel::Nodes::NamedFunction.new(
      'COALESCE',
      [Arel::Nodes::Grouping.new(predicate), Arel::Nodes.build_quoted(false)]
    )
  end

  def negate(predicate)
    Arel::Nodes::Not.new(Arel::Nodes::Grouping.new(predicate))
  end
end
