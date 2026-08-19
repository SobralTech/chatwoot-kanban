# The operation and its parameters, resolved against one board. Everything the payload
# can get wrong is caught here, once, so a bad param fails the whole request with a
# single code instead of producing one identical failure row per card.
class KanbanCards::BulkActionRequest
  MAX_CARDS = 100
  OPERATIONS = %w[move assign label clear_labels priority lose delete].freeze

  class Error < ArgumentError
    attr_reader :code

    def initialize(code)
      @code = code
      super(code)
    end
  end

  def initialize(kanban_board:, operation:, card_ids:, payload: {})
    @kanban_board = kanban_board
    @operation = operation.to_s
    @card_ids = Array(card_ids).filter_map(&:presence).map(&:to_i).uniq
    @payload = payload.to_h.deep_symbolize_keys
  end

  attr_reader :operation, :card_ids

  def validate!
    raise Error, 'bulk_action_limit_exceeded' if card_ids.length > MAX_CARDS
    raise Error, 'bulk_action_not_supported' unless OPERATIONS.include?(operation)
    raise Error, 'card_ids_required' if card_ids.empty?

    validate_payload!
  end

  def move_stage
    @move_stage ||= kanban_board.kanban_stages.active.find_by(id: payload[:kanban_stage_id])
  end

  def lost_stage
    @lost_stage ||= kanban_board.lost_stage
  end

  # `move` and `lose` are the same transition; only the destination differs, and which
  # destination applies is a property of the operation rather than of the caller.
  def target_stage
    operation == 'lose' ? lost_stage : move_stage
  end

  def assignee_ids
    @assignee_ids ||= Array(payload[:assignee_ids]).filter_map(&:presence).map(&:to_i).uniq
  end

  def labels
    @labels ||= Array(payload[:labels]).filter_map { |value| value.to_s.strip.presence }.uniq
  end

  def priority
    payload[:priority].presence
  end

  def reason_id
    payload[:kanban_reason_id]
  end

  private

  attr_reader :kanban_board, :payload

  def validate_payload!
    case operation
    when 'move' then validate_move!
    when 'lose' then validate_lose!
    when 'assign' then validate_assignees!
    when 'label' then validate_labels!
    when 'priority' then validate_priority!
    end
  end

  def validate_move!
    raise Error, 'target_stage_required' unless move_stage
    raise Error, 'terminal_stage_move_not_supported' if KanbanStage.special_stage_ids(kanban_board).include?(move_stage.id)
  end

  def validate_lose!
    raise Error, 'lost_stage_not_found' unless lost_stage&.active?
    raise Error, 'lost_reason_required' if kanban_board.lost_reason_required? && reason_id.blank?
  end

  def validate_assignees!
    unknown_ids = assignee_ids - kanban_board.assignable_users.where(id: assignee_ids).pluck(:id)
    raise Error, 'unknown_assignees' if unknown_ids.present?
  end

  def validate_labels!
    raise Error, 'label_required' if labels.blank?

    known_labels = kanban_board.account.labels.where(title: labels).pluck(:title)
    raise Error, 'unknown_label' if (labels - known_labels).present?
  end

  def validate_priority!
    raise Error, 'unknown_priority' unless priority.nil? || KanbanCard.priorities.key?(priority)
  end
end
