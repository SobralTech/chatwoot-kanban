# rubocop:disable Metrics/ClassLength
class KanbanAutomations::ActionExecutor
  Result = Data.define(:status, :event_name, :event_recorded, :metadata)
  ACTION_HANDLERS = {
    'move_to_stage' => :move_to_stage,
    'assign_agents' => :assign_agents,
    'set_priority' => :set_priority,
    'add_label' => :add_label,
    'remove_label' => :remove_label,
    'set_due_at' => :set_due_at,
    'create_note' => :create_note,
    'send_message' => :send_message,
    'send_private_note' => :send_private_note,
    'mark_as_lost' => :mark_as_lost,
    'create_card_in_board' => :create_card_in_board
  }.freeze

  SKIPPED_ACTIONS = {
    'notify_agents' => 'aguardando notificações (S24)',
    'send_webhook' => 'aguardando guardrails (S21)'
  }.freeze

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
    Array(rule.actions).each do |raw_action|
      execute(raw_action.with_indifferent_access)
    end
  ensure
    persist_automation_log if @automation_started
    Current.reset
  end

  private

  attr_reader :card, :rule, :context

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
    action_result(action[:action_name].to_s, action_params)
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

  def action_result(action_name, action_params)
    return skipped_result(action_name, SKIPPED_ACTIONS.fetch(action_name)) if SKIPPED_ACTIONS.key?(action_name)

    dispatch_action(action_name, action_params, persist: !rule.dry_run?)
  end

  def send_message(params, persist:)
    send_automated_message(params, persist: persist, private_note: false)
  end

  def send_private_note(params, persist:)
    return skipped_result('send_private_note', 'card_without_conversation') if card.conversation.blank?

    result = KanbanAutomations::MessagingAction.perform(
      card: card,
      rule: rule,
      rendered_content: KanbanAutomations::MessagingAction.render_content(card: card, content: params[:content]),
      private_note: true,
      persist: persist
    )
    executed_result(metadata: result)
  end

  def send_automated_message(params, persist:, private_note:)
    rendered_content = KanbanAutomations::MessagingAction.render_content(card: card, content: params[:content])
    guardrail = KanbanAutomations::GuardrailService.check(
      card: card,
      rule: rule,
      action_params: params,
      context: context
    )
    return skipped_result('send_message', guardrail.reason, guardrail.metadata.merge(content: rendered_content)) unless guardrail.allowed?

    result = KanbanAutomations::MessagingAction.perform(
      card: card,
      rule: rule,
      rendered_content: rendered_content,
      private_note: private_note,
      persist: persist
    )
    executed_result(metadata: result)
  end

  def dispatch_action(action_name, params, persist:)
    handler = ACTION_HANDLERS[action_name]
    return skipped_result(action_name, 'ação desconhecida') unless handler

    send(handler, params, persist: persist)
  end

  def move_to_stage(params, persist:)
    target_stage = board.kanban_stages.active.find(params[:stage_id])
    raise ArgumentError, 'stage_id cannot point to a terminal stage' if terminal_stage?(target_stage)

    transition = build_transition(target_stage)
    raise ArgumentError, transition.error[:error] if transition.error

    return executed_result(metadata: { stage_id: target_stage.id }) unless persist

    KanbanCard.transaction do
      transition.apply!
      transition.record_event!
    end

    executed_result(event_name: transition.automation_event_name,
                    event_recorded: transition.automation_event_name.present?,
                    metadata: { stage_id: target_stage.id })
  end

  def mark_as_lost(params, persist:)
    target_stage = board.lost_stage
    raise ActiveRecord::RecordNotFound, 'lost stage not found' unless target_stage&.active?

    transition = build_transition(target_stage, kanban_reason_id: params[:reason_id])
    raise ArgumentError, transition.error[:error] if transition.error

    return executed_result(metadata: { stage_id: target_stage.id }) unless persist

    KanbanCard.transaction do
      transition.apply!
      transition.record_event!
    end

    executed_result(event_name: transition.automation_event_name,
                    event_recorded: transition.automation_event_name.present?,
                    metadata: { stage_id: target_stage.id, reason_id: params[:reason_id] })
  end

  def terminal_stage?(stage)
    KanbanStage.special_stage_ids(board).include?(stage.id)
  end

  def build_transition(target_stage, kanban_reason_id: nil)
    KanbanCards::StageTransition.new(
      kanban_board: board,
      kanban_card: card,
      target_stage: target_stage,
      kanban_reason_id: kanban_reason_id,
      user: nil,
      event_metadata: automation_metadata
    )
  end

  def assign_agents(params, persist:)
    previous_ids = card.kanban_card_assignees.pluck(:user_id)
    next_ids = assignment_ids(params)
    changed = previous_ids.sort != next_ids.sort

    if persist
      card.update_assignees!(next_ids)
      KanbanCards::RecordEventService.assignees_changed(
        card: card, from: previous_ids, to: next_ids, user: nil, metadata: automation_metadata
      )
    end

    executed_result(event_recorded: changed, metadata: { assignee_ids: next_ids })
  end

  def assignment_ids(params)
    mode = params[:mode].to_s
    requested_ids = Array(params[:agent_ids]).filter_map { |id| Integer(id, exception: false) }
    assignable_ids = board.assignable_users.where(id: requested_ids).pluck(:id)

    case mode
    when 'set' then assignable_ids
    when 'add' then (card.kanban_card_assignees.pluck(:user_id) + assignable_ids).uniq
    when 'round_robin' then [round_robin_agent_id].compact
    else
      raise ArgumentError, "unsupported assignment mode: #{mode}"
    end
  end

  def round_robin_agent_id
    agents = board.assignable_users.order(:id).to_a
    return if agents.empty?

    active_card_counts = KanbanCard.active
                                   .where(kanban_board_id: board.id)
                                   .where.not(kanban_stage_id: KanbanStage.special_stage_ids(board))
                                   .joins(:kanban_card_assignees)
                                   .where(kanban_card_assignees: { user_id: agents.map(&:id) })
                                   .group(:user_id)
                                   .count
    agents.min_by { |agent| [active_card_counts.fetch(agent.id, 0), agent.id] }.id
  end

  def set_priority(params, persist:)
    priority = params[:priority].presence
    raise ArgumentError, "unsupported priority: #{priority}" if priority.present? && KanbanCard.priorities.key?(priority.to_s) == false

    previous_priority = card.priority
    card.update!(priority: priority) if persist
    changed = previous_priority != priority
    if persist
      KanbanCards::RecordEventService.attribute_changed(
        card: card, event_type: 'priority_changed', from: previous_priority, to: priority,
        user: nil, metadata: automation_metadata
      )
    end

    executed_result(event_recorded: changed, metadata: { from: previous_priority, to: priority })
  end

  def change_labels(params, add:, persist:)
    previous_labels = card.label_list.to_a
    labels = Array(params[:labels]).filter_map { |label| label.to_s.strip.presence }.uniq
    next_labels = add ? (previous_labels + labels).uniq : previous_labels - labels

    card.update_labels(next_labels) if persist
    if persist
      KanbanCards::RecordEventService.labels_changed(
        card: card, from: previous_labels, to: next_labels, user: nil, metadata: automation_metadata
      )
    end

    executed_result(event_recorded: previous_labels != next_labels, metadata: { from: previous_labels, to: next_labels })
  end

  def add_label(params, persist:)
    change_labels(params, add: true, persist: persist)
  end

  def remove_label(params, persist:)
    change_labels(params, add: false, persist: persist)
  end

  def set_due_at(params, persist:)
    due_at = due_at_from(params)
    previous_due_at = card.due_at
    card.update!(due_at: due_at) if persist
    changed = previous_due_at != due_at
    if persist
      KanbanCards::RecordEventService.attribute_changed(
        card: card, event_type: 'due_at_changed', from: previous_due_at, to: due_at,
        user: nil, metadata: automation_metadata
      )
    end

    executed_result(event_recorded: changed, metadata: { from: previous_due_at, to: due_at })
  end

  def due_at_from(params)
    days = params[:days].to_i
    return Time.current + days.days unless ActiveModel::Type::Boolean.new.cast(params[:business_days])

    due_at = Time.current
    step = days.negative? ? -1 : 1
    days.abs.times do
      due_at += step.days
      due_at += step.days while due_at.saturday? || due_at.sunday?
    end
    due_at
  end

  def create_note(params, persist:)
    content = render_template(params[:content].to_s)
    raise ArgumentError, 'note content cannot be blank' if content.blank?

    card.kanban_card_notes.create!(account: account, content: content, user: nil) if persist
    executed_result(metadata: { content: content })
  end

  def create_card_in_board(params, persist:)
    target_board = find_target_board(params)
    target_stage = target_board.kanban_stages.active.find(params[:stage_id])
    subject = rendered_card_subject(params)
    metadata = { kanban_board_id: target_board.id, stage_id: target_stage.id, subject: subject }
    return executed_result(metadata: metadata) unless persist

    create_target_card(target_board, target_stage, subject)
    executed_result(metadata: metadata)
  end

  def find_target_board(params)
    KanbanBoard.where(account_id: account.id).find(params[:kanban_board_id])
  end

  def rendered_card_subject(params)
    subject = render_template(params[:subject].presence || card.subject.to_s)
    raise ArgumentError, 'card subject cannot be blank' if subject.blank?

    subject
  end

  def create_target_card(target_board, target_stage, subject)
    KanbanCards::CreateManualCardService.new(
      account: account,
      user: nil,
      kanban_board: target_board,
      kanban_stage: target_stage,
      contact: card.contact,
      inbox: card.inbox,
      subject: subject,
      conversation: card.conversation,
      context: automation_context,
      automation: true
    ).perform!
  end

  def render_template(value)
    KanbanAutomations::MessagingAction.render_content(card: card, content: value)
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
      rule: rule,
      status: result.status,
      metadata: result.metadata
    )
  end

  def executed_result(event_name: nil, event_recorded: false, metadata: {})
    Result.new(status: 'executed', event_name: event_name, event_recorded: event_recorded, metadata: metadata)
  end

  def skipped_result(action_name, reason, metadata = {})
    Result.new(status: 'skipped', event_name: nil, event_recorded: false,
               metadata: { action_name: action_name, reason: reason }.merge(metadata))
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

  def automations_enabled?
    KanbanAutomations::GuardrailService.automations_enabled?(card)
  end

  def automation_metadata
    { automation_rule_id: rule.id }
  end

  def automation_context
    {
      triggered_by_rule_id: rule.id,
      automation_depth: context[:automation_depth].to_i + 1
    }
  end

  def account
    card.account
  end

  def board
    card.kanban_board
  end
end
# rubocop:enable Metrics/ClassLength
