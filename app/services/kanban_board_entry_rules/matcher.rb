# Decides whether a conversation satisfies an entry rule. The rule's inbox side is not
# checked here: the inbox is SQL (the join table), so callers narrow by inbox before
# reaching this, and what is left is the four conditions that only Ruby can answer.
#
# A rule with no conditions matches every conversation in its inboxes -- naming the
# inboxes is the condition.
class KanbanBoardEntryRules::Matcher
  extend KanbanConditions::Coercions

  NUMERIC_ATTRIBUTES = %w[assignee_id team_id].freeze

  ATTRIBUTES = {
    # `cached_label_list` is denormalised onto the conversation, so matching a page of
    # them costs no query per conversation.
    'labels' => ->(conversation) { conversation.cached_label_list_array },
    'assignee_id' => ->(conversation) { conversation.assignee_id },
    'team_id' => ->(conversation) { conversation.team_id },
    'priority' => ->(conversation) { conversation.priority }
  }.freeze

  # Each operator sees the live value already normalised to an array, so "no assignee" and
  # "no labels" are both the empty list and the NONE_VALUE sentinel matches either.
  OPERATORS = {
    'is_one_of' => ->(values, expected, numeric) { any_match?(values, expected, numeric) },
    'is_not_one_of' => ->(values, expected, numeric) { !any_match?(values, expected, numeric) },
    'includes_any' => ->(values, expected, numeric) { any_match?(values, expected, numeric) },
    'includes_all' => ->(values, expected, numeric) { all_match?(values, expected, numeric) },
    'not_includes' => ->(values, expected, numeric) { !any_match?(values, expected, numeric) }
  }.freeze

  def self.match?(conversation, rule)
    new(conversation, rule).match?
  end

  def initialize(conversation, rule)
    @conversation = conversation
    @rule = rule
  end

  def match?
    Array(rule.conditions).all? { |condition| condition_matches?(condition.with_indifferent_access) }
  end

  private

  attr_reader :conversation, :rule

  def condition_matches?(condition)
    attribute_key = condition[:attribute_key].to_s
    attribute = ATTRIBUTES[attribute_key]
    operator = OPERATORS[condition[:filter_operator].to_s]
    return false unless attribute && operator

    operator.call(
      Array.wrap(attribute.call(conversation)).compact,
      Array(condition[:values]),
      NUMERIC_ATTRIBUTES.include?(attribute_key)
    )
  end

  class << self
    private

    def any_match?(values, expected_values, numeric)
      expected_values.any? { |expected| expected_matches?(values, expected, numeric) }
    end

    def all_match?(values, expected_values, numeric)
      expected_values.all? { |expected| expected_matches?(values, expected, numeric) }
    end

    def expected_matches?(values, expected, numeric)
      return values.empty? if expected.to_s == KanbanBoardEntryRule::NONE_VALUE

      values.any? { |value| scalar_equal?(value, expected, numeric: numeric) }
    end
  end
end
