# The catalogue of things a Kanban automation rule can do to a card. One instance per
# rule run; `call` turns an action name plus its params into a Result the executor
# records. Nothing here knows about logging, timelines or dry run -- the executor owns
# that, and a simulated run is unwound by the transaction it opens.
class KanbanAutomations::CardActions
  Result = Data.define(:status, :event_name, :event_recorded, :metadata)

  HANDLERS = {
    'move_to_stage' => :move_to_stage,
    'assign_agents' => :assign_agents,
    'set_priority' => :apply_priority,
    'add_label' => :add_label,
    'remove_label' => :remove_label,
    'set_due_at' => :apply_due_at,
    'create_note' => :create_note,
    'send_message' => :send_message,
    'send_private_note' => :send_private_note,
    'mark_as_lost' => :mark_as_lost,
    'create_card_in_board' => :create_card_in_board
  }.freeze

  # Actions the vocabulary accepts but the engine does not perform yet.
  UNAVAILABLE = {
    'notify_agents' => 'agent notifications are not available yet',
    'send_webhook' => 'outbound webhooks are not available yet'
  }.freeze

  def initialize(card:, rule:, context: {})
    @card = card
    @rule = rule
    @context = context
  end

  def call(action_name, params)
    return skipped_result(action_name, UNAVAILABLE.fetch(action_name)) if UNAVAILABLE.key?(action_name)

    handler = HANDLERS[action_name]
    return skipped_result(action_name, 'unknown action') unless handler

    send(handler, params)
  end

  private

  attr_reader :card, :rule, :context

  def send_message(params)
    rendered_content = render_template(params[:content].to_s)
    guardrail = KanbanAutomations::GuardrailService.check(card: card, rule: rule, action_params: params, context: context)
    return skipped_result('send_message', guardrail.reason, content: rendered_content) unless guardrail.allowed?

    deliver(rendered_content, private_note: false)
  end

  # A private note never reaches the customer, so it skips the guardrails.
  def send_private_note(params)
    return skipped_result('send_private_note', 'card_without_conversation') if card.conversation.blank?

    deliver(render_template(params[:content].to_s), private_note: true)
  end

  def deliver(rendered_content, private_note:)
    result = KanbanAutomations::MessagingAction.perform(
      card: card,
      rule: rule,
      rendered_content: rendered_content,
      private_note: private_note,
      persist: !rule.dry_run?
    )
    executed_result(metadata: result)
  end

  def move_to_stage(params)
    target_stage = board.kanban_stages.active.find(params[:stage_id])
    raise ArgumentError, 'stage_id cannot point to a terminal stage' if terminal_stage?(target_stage)

    apply_transition(target_stage)
  end

  def mark_as_lost(params)
    target_stage = board.lost_stage
    raise ActiveRecord::RecordNotFound, 'lost stage not found' unless target_stage&.active?

    apply_transition(target_stage, kanban_reason_id: params[:reason_id], metadata: { reason_id: params[:reason_id] })
  end

  def apply_transition(target_stage, kanban_reason_id: nil, metadata: {})
    transition = build_transition(target_stage, kanban_reason_id: kanban_reason_id)
    raise ArgumentError, transition.error[:error] if transition.error

    KanbanCard.transaction do
      transition.apply!
      transition.record_event!
    end

    executed_result(event_name: transition.automation_event_name,
                    event_recorded: transition.automation_event_name.present?,
                    metadata: metadata.merge(stage_id: target_stage.id))
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
      user: nil
    )
  end

  def assign_agents(params)
    previous_ids = card.kanban_card_assignees.pluck(:user_id)
    next_ids = KanbanAutomations::AgentAssignment.resolve(board: board, card: card, params: params)

    card.update_assignees!(next_ids)
    KanbanCards::RecordEventService.assignees_changed(card: card, from: previous_ids, to: next_ids, user: nil)

    executed_result(event_recorded: previous_ids.sort != next_ids.sort, metadata: { assignee_ids: next_ids })
  end

  def apply_priority(params)
    priority = params[:priority].presence
    raise ArgumentError, "unsupported priority: #{priority}" if priority.present? && !KanbanCard.priorities.key?(priority.to_s)

    previous_priority = card.priority
    card.update!(priority: priority)
    KanbanCards::RecordEventService.attribute_changed(
      card: card, event_type: 'priority_changed', from: previous_priority, to: priority, user: nil
    )

    executed_result(event_recorded: previous_priority != priority, metadata: { from: previous_priority, to: priority })
  end

  def change_labels(params, add:)
    previous_labels = card.label_list.to_a
    labels = Array(params[:labels]).filter_map { |label| label.to_s.strip.presence }.uniq
    next_labels = add ? (previous_labels + labels).uniq : previous_labels - labels

    card.update_labels(next_labels)
    KanbanCards::RecordEventService.labels_changed(card: card, from: previous_labels, to: next_labels, user: nil)

    executed_result(event_recorded: previous_labels != next_labels, metadata: { from: previous_labels, to: next_labels })
  end

  def add_label(params)
    change_labels(params, add: true)
  end

  def remove_label(params)
    change_labels(params, add: false)
  end

  def apply_due_at(params)
    due_at = due_at_from(params)
    previous_due_at = card.due_at

    card.update!(due_at: due_at)
    KanbanCards::RecordEventService.attribute_changed(
      card: card, event_type: 'due_at_changed', from: previous_due_at, to: due_at, user: nil
    )

    executed_result(event_recorded: previous_due_at != due_at, metadata: { from: previous_due_at, to: due_at })
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

  def create_note(params)
    content = render_template(params[:content].to_s)
    raise ArgumentError, 'note content cannot be blank' if content.blank?

    card.kanban_card_notes.create!(account: account, content: content, user: nil)
    executed_result(metadata: { content: content })
  end

  # Creating the card dispatches its own realtime event, which a rollback cannot take
  # back, so this one checks the mode instead of relying on the transaction.
  def create_card_in_board(params)
    spawn = KanbanAutomations::CrossBoardCard.new(card: card, rule: rule, context: context)
    metadata = spawn.describe(params)
    spawn.create!(params) unless rule.dry_run?

    executed_result(metadata: metadata)
  end

  def render_template(value)
    KanbanAutomations::MessagingAction.render_content(card: card, content: value)
  end

  def executed_result(event_name: nil, event_recorded: false, metadata: {})
    Result.new(status: 'executed', event_name: event_name, event_recorded: event_recorded, metadata: metadata)
  end

  def skipped_result(action_name, reason, metadata = {})
    Result.new(status: 'skipped', event_name: nil, event_recorded: false,
               metadata: { action_name: action_name, reason: reason }.merge(metadata))
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
