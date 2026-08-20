class KanbanStages::MoveToBoardService
  Result = Data.define(:success?, :error, :blocked, :source_board_id, :moved_count)

  def initialize(stage:, target_board:, position:, user:)
    @stage = stage
    @target_board = target_board
    @position = position
    @user = user
    @source_board = stage.kanban_board
  end

  def perform!
    return failure('special_stage_cannot_move_board') if special_stage?
    return failure('last_stage_cannot_move_board') if last_regular_stage?
    return failure('stage_name_taken') if stage_name_taken?

    blocked = blocked_cards
    return failure('stage_cards_blocked', blocked: blocked) if blocked.present?

    move_stage!
  rescue ActiveRecord::RecordNotUnique
    failure('stage_cards_blocked', blocked: { 'card_already_in_target_board' => 1 })
  end

  private

  def special_stage?
    KanbanStage.special_stage_ids(@source_board).include?(@stage.id)
  end

  def last_regular_stage?
    regular_stage_ids = KanbanStage.special_stage_ids(@source_board)
    @source_board.kanban_stages.active.where.not(id: regular_stage_ids).where.not(id: @stage.id).none?
  end

  def stage_name_taken?
    @target_board.kanban_stages.active.exists?(name: @stage.name)
  end

  def active_cards
    @stage.kanban_cards.active
  end

  def blocked_cards
    blocked = {}

    blocked_inbox_ids = active_cards.distinct.pluck(:inbox_id).reject do |inbox_id|
      @target_board.inbox_allowed?(inbox_id)
    end
    blocked['inbox_not_allowed'] = active_cards.where(inbox_id: blocked_inbox_ids).count if blocked_inbox_ids.present?

    duplicate_count = duplicate_card_ids.size
    blocked['card_already_in_target_board'] = duplicate_count if duplicate_count.positive?

    blocked
  end

  def duplicate_card_ids
    active_cards
      .where.not(normalized_subject: nil)
      .joins(<<~SQL.squish)
        INNER JOIN kanban_cards target_cards
          ON target_cards.kanban_board_id = #{@target_board.id}
          AND target_cards.active = TRUE
          AND target_cards.inbox_id = kanban_cards.inbox_id
          AND target_cards.normalized_subject = kanban_cards.normalized_subject
          AND target_cards.origin = kanban_cards.origin
          AND (
            (kanban_cards.origin = 'conversation' AND target_cards.conversation_id = kanban_cards.conversation_id)
            OR (kanban_cards.origin = 'manual' AND target_cards.contact_id = kanban_cards.contact_id)
          )
      SQL
      .distinct
      .pluck('kanban_cards.id')
  end

  def move_stage!
    cards = active_cards
    card_attributes = cards.pluck(:id, :kanban_reason_id).to_h
    card_ids = card_attributes.keys
    target_position = requested_target_position

    KanbanStage.transaction do
      lock_move_records!
      move_stage_records!(cards, target_position)

      dropped_field_keys = remap_field_values!(card_ids)
      repoint_card_events!(card_ids)
      record_board_changed_events!(card_ids, card_attributes, dropped_field_keys)
      KanbanStage.normalize_positions_for_board!(@source_board)
      KanbanStage.normalize_positions_for_board!(@target_board)
    end

    success(card_ids.length)
  end

  def lock_move_records!
    KanbanStage.lock_reorder_stages_for_board!([@source_board, @target_board])
    KanbanCard.lock_active_cards_for_stages!(@source_board, [@stage.id])
  end

  def move_stage_records!(cards, target_position)
    KanbanStage.shift_active_positions_from!(@target_board, target_position)
    @stage.update!(kanban_board: @target_board, position: target_position)
    # The stage and its cards move as one bulk operation by design.
    # rubocop:disable Rails/SkipsModelValidations
    cards.update_all(
      kanban_board_id: @target_board.id,
      kanban_reason_id: nil,
      previous_stage_id: nil,
      updated_at: Time.current
    )
    # rubocop:enable Rails/SkipsModelValidations
  end

  def requested_target_position
    maximum_position = KanbanStage.next_active_position(@target_board)
    (@position.presence || maximum_position).to_i.clamp(1, maximum_position)
  end

  def remap_field_values!(card_ids)
    dropped_field_keys = Hash.new { |hash, card_id| hash[card_id] = [] }
    target_fields = target_fields_by_signature

    @source_board.kanban_custom_fields.active.each do |source_field|
      remap_field_values_for(source_field, card_ids, target_fields, dropped_field_keys)
    end

    dropped_field_keys.transform_values { |keys| keys.uniq.sort }
  end

  def target_fields_by_signature
    @target_board.kanban_custom_fields.active.index_by do |field|
      [field.key, field.field_type, field.multiple]
    end
  end

  def remap_field_values_for(source_field, card_ids, target_fields, dropped_field_keys)
    scope = KanbanCardFieldValue.where(kanban_card_id: card_ids, kanban_custom_field_id: source_field.id)
    target_field = target_fields[[source_field.key, source_field.field_type, source_field.multiple]]

    if target_field
      # Field values are already scoped to the moved cards and remapped by signature.
      # rubocop:disable Rails/SkipsModelValidations
      scope.update_all(kanban_custom_field_id: target_field.id)
      # rubocop:enable Rails/SkipsModelValidations
    else
      scope.pluck(:kanban_card_id).each { |card_id| dropped_field_keys[card_id] << source_field.key }
      scope.delete_all
    end
  end

  def repoint_card_events!(card_ids)
    # Historical events follow the cards to keep their board-scoped timeline intact.
    # rubocop:disable Rails/SkipsModelValidations
    KanbanCardEvent.where(kanban_card_id: card_ids).update_all(kanban_board_id: @target_board.id)
    # rubocop:enable Rails/SkipsModelValidations
  end

  def record_board_changed_events!(card_ids, card_attributes, dropped_field_keys)
    return if card_ids.empty?

    recorded_at = Time.current
    # rubocop:disable Rails/SkipsModelValidations
    KanbanCardEvent.insert_all(
      card_ids.map do |card_id|
        {
          account_id: @stage.account_id,
          kanban_card_id: card_id,
          kanban_board_id: @target_board.id,
          event_type: 'board_changed',
          user_id: @user&.id,
          metadata: board_changed_metadata(card_id, card_attributes, dropped_field_keys),
          created_at: recorded_at
        }
      end
    )
    # rubocop:enable Rails/SkipsModelValidations
  end

  def board_changed_metadata(card_id, card_attributes, dropped_field_keys)
    {
      from_board_id: @source_board.id,
      from_board_name: @source_board.name,
      to_board_id: @target_board.id,
      to_board_name: @target_board.name,
      from_stage_id: @stage.id,
      from_stage_name: @stage.name,
      to_stage_id: @stage.id,
      to_stage_name: @stage.name,
      reason_cleared: card_attributes[card_id].present?,
      dropped_field_keys: dropped_field_keys.fetch(card_id, []),
      moved_with_stage: true
    }
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
