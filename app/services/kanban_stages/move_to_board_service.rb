class KanbanStages::MoveToBoardService
  Result = Data.define(:success?, :error, :blocked, :source_board_id, :moved_count)

  def initialize(stage:, target_board:, position:, user:)
    @stage = stage
    @target_board = target_board
    @position = position
    @user = user
    @source_board = stage.kanban_board
  end

  # Only the stage level rules live here. What happens to the cards riding along is
  # KanbanCards::BoardTransfer, shared with the single card move.
  def perform!
    return failure('special_stage_cannot_move_board') if special_stage?
    return failure('last_stage_cannot_move_board') if last_regular_stage?
    return failure('stage_name_taken') if stage_name_taken?

    move_stage!
  rescue ActiveRecord::RecordNotUnique => e
    blocked_after_rollback(e)
  end

  private

  def special_stage?
    KanbanStage.special_stage_ids(@source_board).include?(@stage.id)
  end

  def last_regular_stage?
    special_stage_ids = KanbanStage.special_stage_ids(@source_board)
    @source_board.kanban_stages.active.where.not(id: special_stage_ids).where.not(id: @stage.id).none?
  end

  def stage_name_taken?
    @target_board.kanban_stages.active.exists?(name: @stage.name)
  end

  # Everything the move depends on is read under the lock, so the cards that get checked are
  # exactly the cards that move and the destination's positions cannot shift under the slot
  # this stage is about to take.
  def move_stage!
    blocked = nil
    moved_card_ids = []

    KanbanStage.transaction do
      moved_card_ids = lock_move_records!
      blocked = transfer.blocked_reasons(KanbanCard.where(id: moved_card_ids)).values.tally
      raise ActiveRecord::Rollback if blocked.present?

      move_stage_record!
      transfer.apply!(moved_card_ids)
      KanbanStage.normalize_positions_for_board!(@source_board)
      KanbanStage.normalize_positions_for_board!(@target_board)
    end

    return failure('stage_cards_blocked', blocked: blocked) if blocked.present?

    success(moved_card_ids.length)
  end

  # The pre-check follows the same unique indexes the write does, so reaching here means the
  # destination gained a colliding card while the move was running. The transaction is rolled
  # back by now, so re-running the check reports what actually collided rather than guessing
  # at a count; a violation the check cannot explain is not this service's to relabel.
  def blocked_after_rollback(error)
    blocked = transfer.blocked_reasons(@stage.kanban_cards.active).values.tally
    raise error if blocked.empty?

    failure('stage_cards_blocked', blocked: blocked)
  end

  # The locked rows are the moved set: from here on no card can join or leave the stage.
  def lock_move_records!
    KanbanStage.lock_reorder_stages_for_board!([@source_board, @target_board])
    KanbanCard.lock_active_cards_for_stages!(@source_board, [@stage.id]).map(&:id)
  end

  def move_stage_record!
    target_position = requested_target_position
    KanbanStage.shift_active_positions_from!(@target_board, target_position)
    @stage.update!(kanban_board: @target_board, position: target_position)
  end

  def requested_target_position
    maximum_position = KanbanStage.next_active_position(@target_board)
    (@position.presence || maximum_position).to_i.clamp(1, maximum_position)
  end

  # The stage travels with its cards, so it is both ends of their move.
  def transfer
    @transfer ||= KanbanCards::BoardTransfer.new(
      source_board: @source_board,
      target_board: @target_board,
      from_stage: @stage,
      to_stage: @stage,
      user: @user
    )
  end

  def success(moved_count)
    Result.new(
      success?: true,
      error: nil,
      blocked: nil,
      source_board_id: @source_board.id,
      moved_count: moved_count
    )
  end

  def failure(error, blocked: nil)
    Result.new(
      success?: false,
      error: error,
      blocked: blocked,
      source_board_id: @source_board.id,
      moved_count: 0
    )
  end
end
