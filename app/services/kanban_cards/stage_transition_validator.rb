class KanbanCards::StageTransitionValidator
  def initialize(kanban_board:, kanban_card:, target_stage:, kanban_reason_id: nil)
    @kanban_board = kanban_board
    @kanban_card = kanban_card
    @target_stage = target_stage
    @kanban_reason_id = kanban_reason_id
  end

  def call
    return { error: 'direct_won_lost_transition_not_allowed' } if direct_won_lost_transition?
    return { error: 'lost_reason_required' } if lost_reason_required?

    nil
  end

  def resolved_reason_id
    return if kanban_reason_id.blank?

    if target_stage.id == kanban_board.lost_stage_id
      kanban_board.kanban_reasons.active.lost.find(kanban_reason_id).id
    elsif target_stage.id == kanban_board.won_stage_id
      kanban_board.kanban_reasons.active.won.find(kanban_reason_id).id
    end
  end

  private

  attr_reader :kanban_board, :kanban_card, :target_stage, :kanban_reason_id

  def direct_won_lost_transition?
    [
      kanban_card.kanban_stage_id == kanban_board.won_stage_id && target_stage.id == kanban_board.lost_stage_id,
      kanban_card.kanban_stage_id == kanban_board.lost_stage_id && target_stage.id == kanban_board.won_stage_id
    ].any?
  end

  def lost_reason_required?
    return false if target_stage.id == kanban_card.kanban_stage_id
    return false unless target_stage.id == kanban_board.lost_stage_id
    return false unless kanban_board.lost_reason_required?

    kanban_reason_id.blank?
  end
end
