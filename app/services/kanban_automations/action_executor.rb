class KanbanAutomations::ActionExecutor
  Result = KanbanAutomations::CardActions::Result

  def self.perform(card:, rule:, context: {})
    new(card: card, rule: rule, context: context).perform
  end

  def initialize(card:, rule:, context: {})
    @card = card
    @rule = rule
    @context = context.to_h.with_indifferent_access
  end

  def perform
    return unless automations_enabled?

    @automation_started = true
    Current.executed_by = rule
    run_actions
  ensure
    persist_automation_log if @automation_started
    Current.reset
  end

  private

  attr_reader :card, :rule, :context

  # A simulated run computes everything a real one would and then unwinds, so no
  # handler below has to know which mode it is in. The two effects that escape the
  # transaction -- sending a message and creating a card on another board -- check
  # `rule.dry_run?` where they happen.
  def run_actions
    return execute_actions unless rule.dry_run?

    KanbanCard.transaction do
      execute_actions
      raise ActiveRecord::Rollback
    end
  end

  def execute_actions
    Array(rule.actions).each do |raw_action|
      execute(raw_action.with_indifferent_access)
    end
  end

  def execute(action)
    action_name = action[:action_name].to_s
    result = run_action(action)
    record_result(action_name, result)
  rescue StandardError => e
    handle_action_error(action_name, e)
  end

  def run_action(action)
    action_params = action[:action_params].is_a?(Hash) ? action[:action_params].with_indifferent_access : {}
    card.reload
    actions.call(action[:action_name].to_s, action_params)
  end

  def actions
    @actions ||= KanbanAutomations::CardActions.new(card: card, rule: rule, context: context)
  end

  def record_result(action_name, result)
    record_action_detail(action_name, result)

    if rule.dry_run?
      log_action(action_name, result, dry_run: true)
    else
      record_fallback_event(action_name, result) unless result.event_recorded
      trigger_follow_up(result.event_name)
      log_action(action_name, result, dry_run: false)
    end
  end

  def handle_action_error(action_name, error)
    failure = Result.new(status: 'failed', event_name: nil, event_recorded: false,
                         metadata: { error_class: error.class.name, error: error.message })
    begin
      record_fallback_event(action_name, failure) unless rule.dry_run?
    rescue StandardError => e
      Rails.logger.error("Kanban automation failure event could not be recorded: #{e.message}")
    end
    record_action_detail(action_name, failure)
    log_action(action_name, failure, dry_run: rule.dry_run?)
    ChatwootExceptionTracker.new(error, account: account).capture_exception
  end

  def trigger_follow_up(event_name)
    return if event_name.blank?

    KanbanAutomations::TriggerService.call(
      card: card.reload,
      event_name: event_name,
      user: nil,
      context: automation_context
    )
  end

  def record_fallback_event(action_name, result)
    KanbanCards::RecordEventService.automation_action(
      card: card,
      action_name: action_name,
      status: result.status,
      metadata: result.metadata
    )
  end

  def log_action(action_name, result, dry_run:)
    Rails.logger.info(
      {
        event: 'kanban_automation_action',
        automation_rule_id: rule.id,
        kanban_card_id: card.id,
        action_name: action_name,
        status: dry_run ? 'dry_run' : result.status,
        metadata: result.metadata
      }.to_json
    )
  end

  def record_action_detail(action_name, result)
    @action_details ||= []
    @action_details << {
      action_name: action_name,
      status: result.status,
      metadata: result.metadata
    }
  end

  def persist_automation_log
    KanbanAutomationLog.create!(
      account: account,
      kanban_automation_rule: rule,
      kanban_card: card,
      event_name: rule.event_name,
      status: automation_log_status,
      details: { actions: @action_details || [] }
    )
  rescue StandardError => e
    Rails.logger.error("Kanban automation log could not be recorded: #{e.message}")
  end

  def automation_log_status
    return 'matched' if @action_details.blank?
    return 'simulated' if rule.dry_run?
    return 'failed' if @action_details.any? { |detail| detail[:status] == 'failed' }
    return 'skipped' if @action_details.none? { |detail| detail[:status] == 'executed' }

    'executed'
  end

  def account
    card.account
  end

  # Rules a rule sets off run one level deeper, and TriggerService refuses past two.
  def automation_context
    { triggered_by_rule_id: rule.id, automation_depth: context[:automation_depth].to_i + 1 }
  end

  def automations_enabled?
    KanbanAutomations::GuardrailService.automations_enabled?(card)
  end
end
