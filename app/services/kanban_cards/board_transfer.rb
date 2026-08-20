# Sending cards to another funnel — one card at a time, or a whole stage at once — always runs
# the same rules: the destination has to accept the card's inbox and must not already hold the
# same card; the reason and the stage the card could be reopened into are cleared, because both
# belong to the funnel being left; custom field values are remapped onto the destination's
# fields by signature and dropped when it has none; and the timeline follows the card, so
# deleting the funnel it left cannot take the history along.
class KanbanCards::BoardTransfer
  INBOX_NOT_ALLOWED = 'inbox_not_allowed'.freeze
  DUPLICATE = 'card_already_in_target_board'.freeze

  SIGNATURE_COLUMNS = %i[id origin inbox_id conversation_id contact_id normalized_subject].freeze

  def initialize(source_board:, target_board:, from_stage:, to_stage:, user:)
    @source_board = source_board
    @target_board = target_board
    @from_stage = from_stage
    @to_stage = to_stage
    @user = user
    # The boards always differ, so cards keep their stage only when the stage is what moved.
    @moved_with_stage = from_stage == to_stage
  end

  # One reason per card, resolved in the order a single card move reports them, so callers can
  # count blocked cards without counting the ones that fail both rules twice.
  # => { card_id => INBOX_NOT_ALLOWED | DUPLICATE }
  def blocked_reasons(cards)
    source = cards.select(*SIGNATURE_COLUMNS).to_a
    return {} if source.empty?

    inbox_allowed = source.map(&:inbox_id).uniq.index_with { |inbox_id| @target_board.inbox_allowed?(inbox_id) }
    duplicates = duplicate_card_ids(source)

    source.each_with_object({}) do |card, reasons|
      if !inbox_allowed[card.inbox_id]
        reasons[card.id] = INBOX_NOT_ALLOWED
      elsif duplicates.include?(card.id)
        reasons[card.id] = DUPLICATE
      end
    end
  end

  # The cards land on the destination board first: KanbanCardFieldValue#validate_board_consistency
  # compares the custom field's board against the card's own, so remapping any earlier would
  # point field values at a board the card has not reached yet.
  def apply!(card_ids)
    return if card_ids.empty?

    cleared_reason_card_ids = move_cards!(card_ids)
    dropped_field_keys = remap_field_values!(card_ids)
    repoint_events!(card_ids)
    record_board_changed_events!(card_ids, cleared_reason_card_ids, dropped_field_keys)
  end

  private

  # The destination is matched on the key the partial unique indexes on kanban_cards are built
  # from. Narrowing it by the inboxes and subjects in play keeps the comparison set small.
  def duplicate_card_ids(source)
    signed = source.reject { |card| card.normalized_subject.nil? }
    return Set.new if signed.empty?

    taken = taken_signatures(signed)

    signed.select { |card| taken.include?(card_signature(card)) }.to_set(&:id)
  end

  # Archived cards are not symmetrical here, and the check has to follow the indexes rather
  # than the other way round: index_kanban_cards_on_conversation_subject_unique covers a
  # conversation card whether or not it is still active, while the manual one is scoped to
  # active rows. Checking only active cards would let an archived conversation card through
  # the check and into a constraint violation on the way in.
  def taken_signatures(signed)
    scope = @target_board.kanban_cards
                         .where(inbox_id: signed.map(&:inbox_id).uniq, normalized_subject: signed.map(&:normalized_subject).uniq)
                         .select(*SIGNATURE_COLUMNS)

    scope.where(origin: :conversation).or(scope.where(active: true)).to_set { |card| card_signature(card) }
  end

  # A card without a normalized subject has no signature at all and cannot collide.
  def card_signature(card)
    [card.origin, card.inbox_id, card.conversation? ? card.conversation_id : card.contact_id, card.normalized_subject]
  end

  # The caller has already validated and locked these rows, so the move is a bulk repoint.
  # rubocop:disable Rails/SkipsModelValidations
  def move_cards!(card_ids)
    cards = KanbanCard.where(id: card_ids)
    cleared_reason_card_ids = cards.where.not(kanban_reason_id: nil).pluck(:id).to_set

    cards.update_all(
      kanban_board_id: @target_board.id,
      kanban_reason_id: nil,
      previous_stage_id: nil,
      updated_at: Time.current
    )

    cleared_reason_card_ids
  end

  def remap_field_values!(card_ids)
    dropped_field_keys = Hash.new { |hash, card_id| hash[card_id] = [] }
    target_fields = @target_board.kanban_custom_fields.active.index_by { |field| field_signature(field) }

    @source_board.kanban_custom_fields.active.each do |source_field|
      remap_field_values_for(source_field, target_fields[field_signature(source_field)], card_ids, dropped_field_keys)
    end

    dropped_field_keys.transform_values { |keys| keys.uniq.sort }
  end

  def field_signature(custom_field)
    [custom_field.key, custom_field.field_type, custom_field.multiple]
  end

  def remap_field_values_for(source_field, target_field, card_ids, dropped_field_keys)
    scope = KanbanCardFieldValue.where(kanban_card_id: card_ids, kanban_custom_field_id: source_field.id)

    if target_field
      # Both fields carry the same key, type and cardinality, so the stored value stays valid.
      scope.update_all(kanban_custom_field_id: target_field.id, updated_at: Time.current)
    else
      scope.pluck(:kanban_card_id).each { |card_id| dropped_field_keys[card_id] << source_field.key }
      scope.delete_all
    end
  end

  # The timeline is board scoped and boards clean their events up on delete, so history left
  # behind would disappear the day the funnel the cards came from is removed.
  def repoint_events!(card_ids)
    KanbanCardEvent.where(kanban_card_id: card_ids).update_all(kanban_board_id: @target_board.id)
  end

  # KanbanCardEvent has no callbacks and its only validation is on event_type, which is a
  # literal here, so one insert covers a single card and a whole stage alike.
  def record_board_changed_events!(card_ids, cleared_reason_card_ids, dropped_field_keys)
    recorded_at = Time.current

    KanbanCardEvent.insert_all(
      card_ids.map do |card_id|
        {
          account_id: @target_board.account_id,
          kanban_card_id: card_id,
          kanban_board_id: @target_board.id,
          event_type: 'board_changed',
          user_id: @user&.id,
          metadata: board_changed_metadata(card_id, cleared_reason_card_ids, dropped_field_keys),
          created_at: recorded_at
        }
      end
    )
  end
  # rubocop:enable Rails/SkipsModelValidations

  def board_changed_metadata(card_id, cleared_reason_card_ids, dropped_field_keys)
    {
      from_board_id: @source_board.id,
      from_board_name: @source_board.name,
      to_board_id: @target_board.id,
      to_board_name: @target_board.name,
      from_stage_id: @from_stage.id,
      from_stage_name: @from_stage.name,
      to_stage_id: @to_stage.id,
      to_stage_name: @to_stage.name,
      reason_cleared: cleared_reason_card_ids.include?(card_id),
      dropped_field_keys: dropped_field_keys.fetch(card_id, []),
      moved_with_stage: @moved_with_stage
    }
  end
end
