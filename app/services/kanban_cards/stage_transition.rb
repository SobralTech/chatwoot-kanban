# One card moving from its current stage to a target stage: the rules that block the
# move, the writes that record it, and the stages the board has to refresh afterwards.
# Callers own the surrounding transaction and decide when to flush the timeline event,
# so an update that also touches priority/labels keeps its event ordering.
class KanbanCards::StageTransition
  def initialize(kanban_board:, kanban_card:, target_stage:, kanban_reason_id: nil, user: nil)
    @kanban_board = kanban_board
    @kanban_card = kanban_card
    @target_stage = target_stage
    @kanban_reason_id = kanban_reason_id
    @user = user
    @source_stage = kanban_card.kanban_stage
  end

  attr_reader :source_stage, :target_stage

  def error
    return { error: 'direct_won_lost_transition_not_allowed' } if direct_won_lost_transition?
    return { error: 'lost_reason_required' } if lost_reason_required?

    nil
  end

  def apply!(position: nil)
    kanban_card.reorder_to_position!(kanban_stage: target_stage, position: position || default_position)
    return if same_stage?

    kanban_card.update!(previous_stage_id: source_stage.id) if entering_terminal_stage?
    kanban_card.update!(kanban_reason_id: resolved_reason_id)
  end

  def record_event!
    return if same_stage?

    KanbanCards::RecordEventService.call(
      card: kanban_card,
      event_type: terminal_event_type || 'stage_changed',
      user: user,
      metadata: terminal_event_type ? terminal_event_metadata : stage_event_metadata
    )
  end

  def affected_stage_ids
    [source_stage.id, target_stage.id].uniq
  end

  def default_position
    return kanban_card.position if same_stage?

    next_position
  end

  def next_position
    kanban_board.kanban_cards.active.where(kanban_stage: target_stage).maximum(:position).to_i + 1
  end

  private

  attr_reader :kanban_board, :kanban_card, :kanban_reason_id, :user

  def same_stage?
    source_stage.id == target_stage.id
  end

  def direct_won_lost_transition?
    [
      source_stage.id == kanban_board.won_stage_id && target_stage.id == kanban_board.lost_stage_id,
      source_stage.id == kanban_board.lost_stage_id && target_stage.id == kanban_board.won_stage_id
    ].any?
  end

  def lost_reason_required?
    return false if same_stage?
    return false unless target_stage.id == kanban_board.lost_stage_id
    return false unless kanban_board.lost_reason_required?

    kanban_reason_id.blank?
  end

  def resolved_reason_id
    return if kanban_reason_id.blank?

    if target_stage.id == kanban_board.lost_stage_id
      kanban_board.kanban_reasons.active.lost.find(kanban_reason_id).id
    elsif target_stage.id == kanban_board.won_stage_id
      kanban_board.kanban_reasons.active.won.find(kanban_reason_id).id
    end
  end

  def entering_terminal_stage?
    !terminal_stage?(source_stage.id) && terminal_stage?(target_stage.id)
  end

  def terminal_stage?(stage_id)
    KanbanStage.special_stage_ids(kanban_board).include?(stage_id)
  end

  def terminal_event_type
    return 'won' if target_stage.id == kanban_board.won_stage_id
    return 'lost' if target_stage.id == kanban_board.lost_stage_id

    nil
  end

  def stage_event_metadata
    {
      from_stage_id: source_stage.id,
      to_stage_id: target_stage.id,
      from_stage_name: source_stage.name,
      to_stage_name: target_stage.name
    }
  end

  def terminal_event_metadata
    reason = kanban_board.kanban_reasons.find_by(id: kanban_card.kanban_reason_id)

    { stage_id: target_stage.id, reason_id: reason&.id, reason_title: reason&.title }
  end
end
