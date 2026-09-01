class KanbanAutomations::TriggerService
  MAX_AUTOMATION_DEPTH = 2
  CONTEXT_KEYS = %w[automation_depth triggered_by_rule_id triggered_by_user_id triggered_at].freeze

  def self.call(card:, event_name:, user: nil, context: {})
    new(card: card, event_name: event_name, user: user, context: context).call
  end

  def self.call_many(card_ids:, kanban_board:, event_name:, user: nil, context: {})
    new(card: nil, kanban_board: kanban_board, event_name: event_name, user: user, context: context).call_many(card_ids)
  end

  # This guard is deliberately kept at the synchronous boundary. It prevents an
  # automation-generated event from enqueueing another level once the chain has
  # already crossed two rule boundaries (A moves -> B moves -> A is stopped).
  def initialize(card:, event_name:, user:, context:, kanban_board: nil)
    @card = card
    @kanban_board = kanban_board || card&.kanban_board
    @event_name = event_name.to_s
    @user = user
    @context = context.to_h.with_indifferent_access
  end

  def call
    return :depth_exceeded if automation_depth >= MAX_AUTOMATION_DEPTH
    return if card.blank? || KanbanAutomationRule::EVENTS.exclude?(event_name)
    return :disabled unless automations_enabled?

    rule_ids = active_rule_ids
    return if rule_ids.empty?

    KanbanAutomations::RunRulesJob.perform_later(card.id, rule_ids, event_name, serialized_context)
    :enqueued
  end

  def call_many(card_ids)
    ids = Array(card_ids).compact.uniq
    return if ids.empty? || KanbanAutomationRule::EVENTS.exclude?(event_name)
    return :depth_exceeded if automation_depth >= MAX_AUTOMATION_DEPTH
    return :disabled unless automations_enabled?

    rule_ids = active_rule_ids
    return if rule_ids.empty?

    serialized = serialized_context
    ids.each { |card_id| KanbanAutomations::RunRulesJob.perform_later(card_id, rule_ids, event_name, serialized) }
    :enqueued
  end

  private

  attr_reader :card, :kanban_board, :event_name, :user, :context

  def automation_depth
    context[:automation_depth].to_i
  end

  def active_rule_ids
    kanban_board.kanban_automation_rules
                .active
                .where(event_name: event_name)
                .ordered
                .pluck(:id)
  end

  def automations_enabled?
    KanbanAutomations::GuardrailService.global_enabled? &&
      KanbanAutomations::GuardrailService.board_enabled?(kanban_board)
  end

  def serialized_context
    context.slice(*CONTEXT_KEYS).stringify_keys
           .merge('automation_depth' => automation_depth)
           .merge('triggered_at' => triggered_at.iso8601)
  end

  def triggered_at
    value = context[:triggered_at]
    return value.to_time if value.respond_to?(:to_time)
    return Time.zone.parse(value.to_s) if value.present?

    Time.current
  rescue ArgumentError, TypeError
    Time.current
  end
end
