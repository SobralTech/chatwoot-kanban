# rubocop:disable Metrics/ClassLength
# rubocop:disable Metrics/ParameterLists
class KanbanCards::BulkActionService
  MAX_CARDS = 100
  ACTIONS = %w[move assign label priority lose delete].freeze

  Result = Struct.new(:succeeded, :failed, keyword_init: true)

  class RequestError < ArgumentError
    attr_reader :code

    def initialize(code)
      @code = code
      super(code)
    end
  end

  class LimitExceededError < RequestError; end
  class ReasonRequiredError < RequestError; end

  def initialize(account:, user:, kanban_board:, action:, card_ids:, payload: {})
    @account = account
    @user = user
    @kanban_board = kanban_board
    @action = action.to_s
    @card_ids = Array(card_ids).filter_map(&:presence).map(&:to_i).uniq
    @payload = payload.to_h.deep_symbolize_keys
    @affected_stage_ids = []
  end

  def perform!
    validate_request!

    result = Result.new(succeeded: [], failed: [])
    @card_ids.each { |card_id| process_card(card_id, result) }
    dispatch_affected_stage_events
    result
  end

  private

  attr_reader :account, :user, :kanban_board, :action, :card_ids, :payload, :affected_stage_ids

  def validate_request!
    raise LimitExceededError, 'bulk_action_limit_exceeded' if card_ids.length > MAX_CARDS
    raise RequestError, 'bulk_action_not_supported' unless ACTIONS.include?(action)
    raise RequestError, 'card_ids_required' if card_ids.empty?
    raise ReasonRequiredError, 'lost_reason_required' if loss_reason_required_without_payload?
  end

  def loss_reason_required_without_payload?
    action == 'lose' && kanban_board.lost_reason_required? && reason_id.blank?
  end

  def process_card(card_id, result)
    card = find_card(card_id)
    return add_failure(result, card_id, 'card_not_found') unless card
    return add_failure(result, card_id, 'not_authorized') unless authorized_card?(card)

    stage_ids = KanbanCard.transaction { action_card(card) }
    affected_stage_ids.concat(stage_ids)
    result.succeeded << card.id
  rescue StandardError => e
    result.failed << { id: card_id, error: error_code(e) }
  end

  def find_card(card_id)
    kanban_board.kanban_cards.active
                .joins(:kanban_stage)
                .merge(KanbanStage.active)
                .includes(:kanban_stage, :contact, :inbox, :conversation)
                .find_by(id: card_id)
  end

  def authorized_card?(card)
    policy = KanbanCardPolicy.new(user_context, card)
    policy.public_send(action == 'delete' ? :destroy? : :update?)
  end

  def action_card(card)
    case action
    when 'move' then move_card(card)
    when 'assign' then assign_card(card)
    when 'label' then label_card(card)
    when 'priority' then priority_card(card)
    when 'lose' then lose_card(card)
    when 'delete' then delete_card(card)
    end
  end

  def move_card(card)
    target_stage = target_stage_for_move
    raise RequestError, 'target_stage_required' unless target_stage
    raise RequestError, 'terminal_stage_move_not_supported' if terminal_stage?(target_stage)

    transition = stage_transition(card, target_stage)
    raise RequestError, transition[:error] if transition

    source_stage = card.kanban_stage
    position = payload[:position].presence || target_position(card, target_stage)
    card.reorder_to_position!(kanban_stage: target_stage, position: position)
    update_stage_transition!(card, source_stage, target_stage)
    record_stage_event(card, source_stage, target_stage)

    [source_stage.id, target_stage.id]
  end

  def assign_card(card)
    assignee_ids = requested_assignee_ids
    unknown_ids = assignee_ids - kanban_board.assignable_users.where(id: assignee_ids).pluck(:id)
    raise RequestError, "Unknown assignees: #{unknown_ids.join(', ')}" if unknown_ids.present?

    previous_assignee_ids = card.kanban_card_assignees.pluck(:user_id)
    card.update_assignees!(assignee_ids)
    KanbanCards::RecordEventService.assignees_changed(
      card: card, from: previous_assignee_ids, to: assignee_ids, user: user
    )

    [card.kanban_stage_id]
  end

  def label_card(card)
    labels = requested_labels(card)
    unknown_titles = labels - account.labels.where(title: labels).pluck(:title)
    raise RequestError, "Unknown labels: #{unknown_titles.join(', ')}" if unknown_titles.present?

    previous_labels = card.label_list.to_a
    card.update_labels(labels)
    KanbanCards::RecordEventService.labels_changed(card: card, from: previous_labels, to: labels, user: user)

    [card.kanban_stage_id]
  end

  def priority_card(card)
    previous_priority = card.priority
    card.update!(priority: payload[:priority].presence)
    record_attribute_event(card, 'priority_changed', previous_priority, card.priority)

    [card.kanban_stage_id]
  end

  def lose_card(card)
    target_stage = kanban_board.lost_stage
    raise RequestError, 'lost_stage_not_found' unless target_stage&.active?

    transition = stage_transition(card, target_stage)
    raise RequestError, transition[:error] if transition

    source_stage = card.kanban_stage
    position = payload[:position].presence || target_position(card, target_stage)
    card.reorder_to_position!(kanban_stage: target_stage, position: position)
    update_stage_transition!(card, source_stage, target_stage)
    record_stage_event(card, source_stage, target_stage)

    [source_stage.id, target_stage.id]
  end

  def delete_card(card)
    stage_id = card.kanban_stage_id
    card.deactivate_and_normalize!
    KanbanCards::RecordEventService.card_deleted(card: card, user: user, metadata: { stage_id: stage_id })

    [stage_id]
  end

  def stage_transition(card, target_stage)
    KanbanCards::StageTransitionValidator.new(
      kanban_board: kanban_board,
      kanban_card: card,
      target_stage: target_stage,
      kanban_reason_id: reason_id
    ).call
  end

  def update_stage_transition!(card, source_stage, target_stage)
    return if source_stage.id == target_stage.id

    card.update!(previous_stage_id: source_stage.id) if entering_terminal_stage?(source_stage, target_stage)
    card.update!(kanban_reason_id: resolved_reason_id(card, target_stage))
  end

  def resolved_reason_id(card, target_stage)
    KanbanCards::StageTransitionValidator.new(
      kanban_board: kanban_board,
      kanban_card: card,
      target_stage: target_stage,
      kanban_reason_id: reason_id
    ).resolved_reason_id
  end

  def record_stage_event(card, source_stage, target_stage)
    return if source_stage.id == target_stage.id

    event_type = terminal_event_type(target_stage)
    metadata = if event_type
                 terminal_event_metadata(card, target_stage)
               else
                 {
                   from_stage_id: source_stage.id,
                   to_stage_id: target_stage.id,
                   from_stage_name: source_stage.name,
                   to_stage_name: target_stage.name
                 }
               end

    KanbanCards::RecordEventService.call(card: card, event_type: event_type || 'stage_changed', user: user, metadata: metadata)
  end

  def terminal_event_type(target_stage)
    return 'won' if target_stage.id == kanban_board.won_stage_id
    return 'lost' if target_stage.id == kanban_board.lost_stage_id

    nil
  end

  def terminal_event_metadata(card, target_stage)
    reason = kanban_board.kanban_reasons.find_by(id: card.kanban_reason_id)

    {
      stage_id: target_stage.id,
      reason_id: reason&.id,
      reason_title: reason&.title
    }
  end

  def record_attribute_event(card, event_type, from, to)
    return if from == to

    KanbanCards::RecordEventService.call(card: card, event_type: event_type, user: user, metadata: { from: from, to: to })
  end

  def entering_terminal_stage?(source_stage, target_stage)
    !terminal_stage?(source_stage) && terminal_stage?(target_stage)
  end

  def terminal_stage?(stage)
    KanbanStage.special_stage_ids(kanban_board).include?(stage.id)
  end

  def target_stage_for_move
    stage_id = payload[:kanban_stage_id] || payload[:target_stage_id] || payload[:stage_id]
    return if stage_id.blank?

    kanban_board.kanban_stages.active.find_by(id: stage_id)
  end

  def target_position(card, target_stage)
    return card.position if card.kanban_stage_id == target_stage.id

    kanban_board.kanban_cards.active.where(kanban_stage: target_stage).maximum(:position).to_i + 1
  end

  def requested_assignee_ids
    values = if payload.key?(:assignee_ids)
               payload[:assignee_ids]
             elsif payload.key?(:user_ids)
               payload[:user_ids]
             else
               payload[:assignee_id]
             end

    Array(values).filter_map(&:presence).map(&:to_i).uniq
  end

  def requested_labels(card)
    return Array(payload[:labels]).map(&:to_s).uniq if payload.key?(:labels)

    label = payload[:label].to_s.strip
    raise RequestError, 'label_required' if label.blank?

    (card.label_list.to_a + [label]).uniq
  end

  def reason_id
    payload[:kanban_reason_id] || payload[:reason_id]
  end

  def add_failure(result, card_id, error)
    result.failed << { id: card_id, error: error }
  end

  def error_code(error)
    return error.code if error.respond_to?(:code)
    return 'not_authorized' if error.is_a?(Pundit::NotAuthorizedError)
    return 'card_not_found' if error.is_a?(ActiveRecord::RecordNotFound)
    return error.record.errors.full_messages.to_sentence if error.is_a?(ActiveRecord::RecordInvalid)

    error.message.presence || 'bulk_action_failed'
  end

  def dispatch_affected_stage_events
    affected_stage_ids.compact.uniq.each do |stage_id|
      Rails.configuration.dispatcher.dispatch(
        Events::Types::KANBAN_STAGE_UPDATED,
        Time.zone.now,
        account_id: kanban_board.account_id,
        board_id: kanban_board.id,
        stage_id: stage_id
      )
    end
  end

  def user_context
    @user_context ||= {
      user: user,
      account: account,
      account_user: user.account_users.find_by(account: account)
    }
  end
end
# rubocop:enable Metrics/ParameterLists
# rubocop:enable Metrics/ClassLength
