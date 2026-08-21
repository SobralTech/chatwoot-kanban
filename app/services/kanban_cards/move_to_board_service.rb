class KanbanCards::MoveToBoardService
  Result = Data.define(:success?, :error, :source_stage_id)

  def initialize(card:, target_board:, target_stage_id:, user:)
    @card = card
    @target_board = target_board
    @target_stage_id = target_stage_id
    @user = user
    @source_board = card.kanban_board
    @source_stage = card.kanban_stage
    @source_stage_id = card.kanban_stage_id
  end

  # Picking the stage the card lands in is this service's job; everything that follows from the
  # card changing board belongs to KanbanCards::BoardTransfer, which the whole-stage move shares.
  def perform!
    target_stage = find_target_stage
    return failure('invalid_target_stage') unless valid_target_stage?(target_stage)

    transfer = build_transfer(target_stage)
    blocked = transfer.blocked_reasons(KanbanCard.where(id: @card.id))[@card.id]
    return failure(blocked) if blocked

    move_card!(target_stage, transfer)
    dispatch_move_events
    success
  rescue ActiveRecord::RecordNotUnique
    failure('card_already_in_target_board')
  end

  private

  def build_transfer(target_stage)
    KanbanCards::BoardTransfer.new(
      source_board: @source_board,
      target_board: @target_board,
      from_stage: @source_stage,
      to_stage: target_stage,
      user: @user
    )
  end

  def find_target_stage
    @target_board.kanban_stages.active.find_by(id: @target_stage_id)
  end

  def valid_target_stage?(target_stage)
    target_stage.present? && KanbanStage.special_stage_ids(@target_board).exclude?(target_stage.id)
  end

  # The reason belongs to the funnel the card is leaving, so the board change and the reason
  # clear have to land in the same write: KanbanCard#validate_board_for_reason rejects any
  # state where the two disagree. BoardTransfer writes that transition, and the stage the card
  # lands in is set straight after, once the card is already on the destination.
  def move_card!(target_stage, transfer)
    KanbanCard.transaction do
      target_position = lock_move_records!(target_stage)
      transfer.apply!([@card.id])
      @card.reload.update!(
        kanban_stage: target_stage,
        position: target_position,
        stage_entered_at: Time.current
      )
      normalize_moved_stages!(target_stage)
      @card.reload
    end
  end

  def lock_move_records!(target_stage)
    KanbanCard.lock_reorder_stages!([@source_stage.id, target_stage.id])
    KanbanCard.lock_active_cards_for_stages!(@source_board, [@source_stage.id])
    KanbanCard.lock_active_cards_for_stages!(@target_board, [target_stage.id])
    next_target_position(target_stage)
  end

  def normalize_moved_stages!(target_stage)
    KanbanCard.normalize_positions_for_stage!(kanban_board: @source_board, kanban_stage: @source_stage)
    KanbanCard.normalize_positions_for_stage!(kanban_board: @target_board, kanban_stage: target_stage)
  end

  # Both ends of the move need the card list refreshed, so the source board hears about a
  # removal and the target board about an arrival.
  def dispatch_move_events
    dispatch_card_event(Events::Types::KANBAN_CARD_DELETED, board_id: @source_board.id, stage_id: @source_stage_id)
    dispatch_card_event(Events::Types::KANBAN_CARD_CREATED, board_id: @target_board.id, stage_id: @card.kanban_stage_id)
  end

  def dispatch_card_event(event_name, board_id:, stage_id:)
    KanbanCards::EventDispatcher.card_event(event_name, @card, board_id: board_id, stage_id: stage_id)
  end

  def next_target_position(target_stage)
    @target_board.kanban_cards.active.where(kanban_stage: target_stage).maximum(:position).to_i + 1
  end

  def success
    Result.new(success?: true, error: nil, source_stage_id: @source_stage_id)
  end

  def failure(error)
    Result.new(success?: false, error: error, source_stage_id: @source_stage_id)
  end
end
