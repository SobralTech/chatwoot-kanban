class KanbanCards::MoveToBoardService
  Result = Data.define(:success?, :error, :source_stage_id)

  def initialize(card:, target_board:, target_stage_id:, user:)
    @card = card
    @target_board = target_board
    @target_stage_id = target_stage_id
    @user = user
    @source_stage_id = card.kanban_stage_id
    @dropped_field_keys = []
  end

  def perform!
    source_stage = @card.kanban_stage
    target_stage = find_target_stage

    return failure('invalid_target_stage') unless valid_target_stage?(target_stage)
    return failure('inbox_not_allowed') unless @target_board.inbox_allowed?(@card.inbox_id)
    return failure('card_already_in_target_board') if duplicate_in_target_board?

    move_card!(source_stage, target_stage)
    success
  rescue ActiveRecord::RecordNotUnique
    failure('card_already_in_target_board')
  end

  private

  def find_target_stage
    @target_board.kanban_stages.active.find_by(id: @target_stage_id)
  end

  def valid_target_stage?(target_stage)
    target_stage.present? && KanbanStage.special_stage_ids(@target_board).exclude?(target_stage.id)
  end

  def duplicate_in_target_board?
    return false if @card.normalized_subject.blank?

    duplicate_scope = @target_board.kanban_cards.active.where(
      inbox_id: @card.inbox_id,
      normalized_subject: @card.normalized_subject
    )

    if @card.conversation?
      duplicate_scope.exists?(origin: 'conversation', conversation_id: @card.conversation_id)
    else
      duplicate_scope.exists?(origin: 'manual', contact_id: @card.contact_id)
    end
  end

  def move_card!(source_stage, target_stage)
    source_board = @card.kanban_board
    source_reason_id = @card.kanban_reason_id

    KanbanCard.transaction do
      target_position = lock_move_records!(source_board, source_stage, target_stage)
      update_moved_card!(target_stage, target_position)
      normalize_moved_stages!(source_board, source_stage, target_stage)
      @card.reload
      record_board_changed_event(source_board, source_stage, target_stage, source_reason_id)
    end
  end

  def lock_move_records!(source_board, source_stage, target_stage)
    KanbanCard.lock_reorder_stages!([source_stage.id, target_stage.id])
    KanbanCard.lock_active_cards_for_stages!(source_board, [source_stage.id])
    KanbanCard.lock_active_cards_for_stages!(@target_board, [target_stage.id])
    next_target_position(target_stage)
  end

  # The card has to be persisted on the target board before the field values are repointed:
  # KanbanCardFieldValue#validate_board_consistency compares the new custom field's board
  # against the card's own, so remapping any earlier fails validation.
  def update_moved_card!(target_stage, target_position)
    @card.update!(
      kanban_board: @target_board,
      kanban_stage: target_stage,
      position: target_position,
      kanban_reason_id: nil,
      previous_stage_id: nil,
      stage_entered_at: Time.current
    )
    remap_field_values!
  end

  def normalize_moved_stages!(source_board, source_stage, target_stage)
    KanbanCard.normalize_positions_for_stage!(kanban_board: source_board, kanban_stage: source_stage)
    KanbanCard.normalize_positions_for_stage!(kanban_board: @target_board, kanban_stage: target_stage)
  end

  def record_board_changed_event(source_board, source_stage, target_stage, source_reason_id)
    KanbanCards::RecordEventService.call(
      card: @card,
      event_type: 'board_changed',
      user: @user,
      metadata: board_changed_metadata(source_board, source_stage, target_stage, source_reason_id)
    )
  end

  def next_target_position(target_stage)
    @target_board.kanban_cards.active.where(kanban_stage: target_stage).maximum(:position).to_i + 1
  end

  def remap_field_values!
    target_fields = @target_board.kanban_custom_fields.active.index_by do |field|
      [field.key, field.field_type, field.multiple]
    end

    @card.kanban_card_field_values.includes(:kanban_custom_field).to_a.each do |field_value|
      source_field = field_value.kanban_custom_field
      target_field = target_fields[[source_field.key, source_field.field_type, source_field.multiple]]

      if target_field
        field_value.update!(kanban_custom_field: target_field)
      else
        @dropped_field_keys << source_field.key
        field_value.destroy!
      end
    end
  end

  def board_changed_metadata(source_board, source_stage, target_stage, source_reason_id)
    {
      from_board_id: source_board.id,
      from_board_name: source_board.name,
      to_board_id: @target_board.id,
      to_board_name: @target_board.name,
      from_stage_id: source_stage.id,
      from_stage_name: source_stage.name,
      to_stage_id: target_stage.id,
      to_stage_name: target_stage.name,
      reason_cleared: source_reason_id.present?,
      dropped_field_keys: @dropped_field_keys.uniq.sort
    }
  end

  def success
    Result.new(success?: true, error: nil, source_stage_id: @source_stage_id)
  end

  def failure(error)
    Result.new(success?: false, error: error, source_stage_id: @source_stage_id)
  end
end
