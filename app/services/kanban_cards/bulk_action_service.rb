class KanbanCards::BulkActionService
  Result = Struct.new(:succeeded, :failed, keyword_init: true)

  delegate :operation, :card_ids, :target_stage, :assignee_ids, :labels, :priority, :reason_id, to: :request

  def initialize(user:, kanban_board:, operation:, card_ids:, payload: {})
    @user = user
    @kanban_board = kanban_board
    @request = KanbanCards::BulkActionRequest.new(
      kanban_board: kanban_board, operation: operation, card_ids: card_ids, payload: payload
    )
    @affected_stage_ids = []
  end

  def perform!
    request.validate!

    result = Result.new(succeeded: [], failed: [])
    card_ids.each { |card_id| process_card(card_id, result) }
    dispatch_affected_stage_events
    result
  end

  private

  attr_reader :user, :kanban_board, :request, :affected_stage_ids

  def account
    kanban_board.account
  end

  # The payload was already validated, so anything raised in here is specific to this
  # card and belongs in `failed` rather than failing the whole request.
  def process_card(card_id, result)
    card = find_card(card_id)
    return add_failure(result, card_id, 'card_not_found') unless card
    return add_failure(result, card_id, 'not_authorized') unless authorized_card?(card)

    stage_ids = KanbanCard.transaction { apply_operation(card) }
    affected_stage_ids.concat(stage_ids)
    result.succeeded << card.id
  rescue StandardError => e
    add_failure(result, card_id, error_code(e))
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
    policy.public_send(operation == 'delete' ? :destroy? : :update?)
  end

  def apply_operation(card)
    case operation
    when 'move', 'lose' then move_card(card)
    when 'assign' then assign_card(card)
    when 'label' then label_card(card)
    when 'clear_labels' then clear_labels(card)
    when 'priority' then priority_card(card)
    when 'delete' then delete_card(card)
    end
  end

  def move_card(card)
    stage_transition = KanbanCards::StageTransition.new(
      kanban_board: kanban_board,
      kanban_card: card,
      target_stage: target_stage,
      kanban_reason_id: reason_id,
      user: user
    )
    transition_error = stage_transition.error
    raise KanbanCards::BulkActionRequest::Error, transition_error[:error] if transition_error

    stage_transition.apply!
    stage_transition.record_event!
    stage_transition.affected_stage_ids
  end

  def assign_card(card)
    previous_assignee_ids = card.kanban_card_assignees.pluck(:user_id)
    card.update_assignees!(assignee_ids)
    KanbanCards::RecordEventService.assignees_changed(
      card: card, from: previous_assignee_ids, to: assignee_ids, user: user
    )

    [card.kanban_stage_id]
  end

  # Bulk labelling is additive: it appends to whatever each card already carries.
  def label_card(card)
    replace_labels(card) { |previous_labels| (previous_labels + labels).uniq }
  end

  def clear_labels(card)
    replace_labels(card) { [] }
  end

  def replace_labels(card)
    previous_labels = card.label_list.to_a
    next_labels = yield(previous_labels)
    card.update_labels(next_labels)
    KanbanCards::RecordEventService.labels_changed(card: card, from: previous_labels, to: next_labels, user: user)

    [card.kanban_stage_id]
  end

  def priority_card(card)
    previous_priority = card.priority
    card.update!(priority: priority)
    KanbanCards::RecordEventService.attribute_changed(
      card: card, event_type: 'priority_changed', from: previous_priority, to: card.priority, user: user
    )

    [card.kanban_stage_id]
  end

  def delete_card(card)
    stage_id = card.kanban_stage_id
    card.deactivate_and_normalize!
    KanbanCards::RecordEventService.card_deleted(card: card, user: user, metadata: { stage_id: stage_id })

    [stage_id]
  end

  def add_failure(result, card_id, error)
    result.failed << { id: card_id, error: error }
  end

  # `failed[].error` is always a code the UI can translate, never a message. Anything
  # unexpected is reported rather than smuggled to the client as English prose.
  def error_code(error)
    return error.code if error.is_a?(KanbanCards::BulkActionRequest::Error)
    return 'card_not_found' if error.is_a?(ActiveRecord::RecordNotFound)

    ChatwootExceptionTracker.new(error, user: user, account: account).capture_exception
    'bulk_action_failed'
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
