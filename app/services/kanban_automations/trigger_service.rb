class KanbanAutomations::TriggerService
  MAX_AUTOMATION_DEPTH = 2
  CONTEXT_KEYS = %w[automation_depth triggered_by_rule_id triggered_by_user_id].freeze

  def self.call(card:, event_name:, user: nil, context: {})
    new(card: card, event_name: event_name, user: user, context: context).call
  end

  # This guard is deliberately kept at the synchronous boundary. It prevents an
  # automation-generated event from enqueueing another level once the chain has
  # already crossed two rule boundaries (A moves -> B moves -> A is stopped).
  def initialize(card:, event_name:, user:, context:)
    @card = card
    @event_name = event_name.to_s
    @user = user
    @context = context.to_h.with_indifferent_access
  end

  def call
    return :depth_exceeded if automation_depth >= MAX_AUTOMATION_DEPTH
    return if card.blank? || KanbanAutomationRule::EVENTS.exclude?(event_name)

    rule_ids = active_rule_ids
    return if rule_ids.empty?

    KanbanAutomations::RunRulesJob.perform_later(card.id, rule_ids, event_name, serialized_context)
    :enqueued
  end

  private

  attr_reader :card, :event_name, :user, :context

  def automation_depth
    context[:automation_depth].to_i
  end

  def active_rule_ids
    card.kanban_board.kanban_automation_rules
        .active
        .where(event_name: event_name)
        .ordered
        .pluck(:id)
  end

  def serialized_context
    context.slice(*CONTEXT_KEYS).stringify_keys.merge('automation_depth' => automation_depth)
  end
end
