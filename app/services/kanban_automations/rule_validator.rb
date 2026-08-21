class KanbanAutomations::RuleValidator
  MAX_CONDITIONS = 10
  MAX_ACTIONS = 10
  ASSIGNMENT_MODES = %w[set add round_robin].freeze

  def initialize(rule)
    @rule = rule
    @errors = rule.errors
  end

  def validate
    validate_event_name
    validate_conditions
    validate_actions
  end

  private

  def validate_event_name
    return if KanbanAutomationRule::EVENTS.include?(@rule.event_name.to_s)

    @errors.add(:event_name, "is not supported: #{@rule.event_name}")
  end

  def validate_conditions
    return unless valid_collection?(:conditions, MAX_CONDITIONS)

    @rule.conditions.each_with_index do |raw_condition, index|
      condition = normalized_hash(raw_condition)
      unless condition
        add_item_error(:conditions, index, 'must be an object')
        next
      end

      validate_condition(condition, index)
    end
  end

  def validate_condition(condition, index)
    %i[attribute_key filter_operator values].each do |key|
      validate_required_key(condition, key, :conditions, index)
    end

    attribute_key = condition[:attribute_key].to_s
    filter_operator = condition[:filter_operator].to_s

    unless KanbanAutomationRule::CONDITION_ATTRIBUTES.include?(attribute_key)
      add_item_error(:conditions, index, "attribute_key is not supported: #{attribute_key}")
    end

    unless KanbanAutomationRule::FILTER_OPERATORS.include?(filter_operator)
      add_item_error(:conditions, index, "filter_operator is not supported: #{filter_operator}")
    end

    return if condition[:values].is_a?(Array)

    add_item_error(:conditions, index, 'values must be an array')
  end

  def validate_actions
    return unless valid_collection?(:actions, MAX_ACTIONS)

    @rule.actions.each_with_index do |raw_action, index|
      action = normalized_hash(raw_action)
      unless action
        add_item_error(:actions, index, 'must be an object')
        next
      end

      validate_action(action, index)
    end
  end

  def validate_action(action, index)
    %i[action_name action_params].each do |key|
      validate_required_key(action, key, :actions, index)
    end

    action_name = action[:action_name].to_s
    unless KanbanAutomationRule::ACTION_NAMES.include?(action_name)
      add_item_error(:actions, index, "action_name is not supported: #{action_name}")
      return
    end

    action_params = normalized_hash(action[:action_params])
    unless action_params
      add_item_error(:actions, index, 'action_params must be an object')
      return
    end

    validate_action_params(action_name, action_params, index)
  end

  def validate_action_params(action_name, action_params, index)
    case action_name
    when 'move_to_stage'
      validate_move_to_stage(action_params, index)
    when 'assign_agents'
      validate_assign_agents(action_params, index)
    when 'mark_as_lost'
      find_reason(action_params[:reason_id], index)
    when 'create_card_in_board'
      validate_create_card_in_board(action_params, index)
    end
  end

  def validate_move_to_stage(action_params, index)
    stage = find_stage(action_params[:stage_id], @rule.kanban_board, index)
    return unless stage.present? && KanbanStage.special_stage_ids(@rule.kanban_board).include?(stage.id)

    add_item_error(:actions, index, 'stage_id cannot point to a terminal stage')
  end

  def validate_assign_agents(action_params, index)
    validate_assignment(action_params, index)
    validate_assignment_mode(action_params, index)
  end

  def validate_create_card_in_board(action_params, index)
    find_stage(action_params[:stage_id], find_board(action_params[:kanban_board_id], index), index)
  end

  def validate_assignment(action_params, index)
    agent_ids = action_params[:agent_ids]
    return reject(:actions, index, 'agent_ids must be an array') unless agent_ids.is_a?(Array)

    ids = agent_ids.map { |agent_id| integer_id(agent_id) }
    return reject(:actions, index, 'agent_ids must contain integer ids') if ids.any?(&:nil?)

    return unless ready_for_reference_validation?

    assignable_ids = @rule.kanban_board.assignable_users.where(id: ids).pluck(:id)
    unknown_ids = ids - assignable_ids
    return if unknown_ids.empty?

    add_item_error(:actions, index, "agent_ids are not assignable in this board: #{unknown_ids.join(', ')}")
  end

  def validate_assignment_mode(action_params, index)
    mode = action_params[:mode].to_s
    return if ASSIGNMENT_MODES.include?(mode)

    add_item_error(:actions, index, "mode is not supported: #{mode}")
  end

  def find_stage(stage_id, board, index)
    return unless ready_for_reference_validation? && board.present?

    id = integer_id(stage_id)
    return reject(:actions, index, 'stage_id must be an integer id') unless id

    stage = KanbanStage.find_by(id: id)
    return stage if stage.present? && stage.account_id == @rule.account_id && stage.kanban_board_id == board.id

    reject(:actions, index, 'stage_id must belong to the referenced board and account')
  end

  def find_reason(reason_id, index)
    return unless ready_for_reference_validation?

    id = integer_id(reason_id)
    return reject(:actions, index, 'reason_id must be an integer id') unless id

    reason = KanbanReason.find_by(id: id)
    return reason if reason.present? && reason.account_id == @rule.account_id && reason.kanban_board_id == @rule.kanban_board_id

    reject(:actions, index, 'reason_id must belong to this board and account')
  end

  def find_board(board_id, index)
    return unless ready_for_reference_validation?

    id = integer_id(board_id)
    return reject(:actions, index, 'kanban_board_id must be an integer id') unless id

    board = KanbanBoard.find_by(id: id)
    return board if board.present? && board.account_id == @rule.account_id

    reject(:actions, index, 'kanban_board_id must belong to this account')
  end

  def validate_required_key(hash, key, attribute, index)
    add_item_error(attribute, index, "#{key} is required") unless hash.key?(key) && !hash[key].nil?
  end

  def valid_collection?(attribute, maximum)
    collection = @rule.public_send(attribute)
    unless collection.is_a?(Array)
      @errors.add(attribute, 'must be an array')
      return false
    end

    @errors.add(attribute, "cannot contain more than #{maximum} items") if collection.size > maximum

    true
  end

  # Strong parameters are not Hashes, so both shapes are named. Asking for to_h instead
  # would accept nil and Array too, and leave the 'must be an object' error unreachable.
  def normalized_hash(value)
    return value.with_indifferent_access if value.is_a?(Hash)
    return value.to_h.with_indifferent_access if value.is_a?(ActionController::Parameters)

    nil
  end

  def integer_id(value)
    Integer(value)
  rescue ArgumentError, TypeError
    nil
  end

  def ready_for_reference_validation?
    @rule.account_id.present? && @rule.kanban_board.present? && @rule.account_id == @rule.kanban_board.account_id
  end

  def add_item_error(attribute, index, message)
    @errors.add(attribute, "#{attribute}[#{index}] #{message}")
    nil
  end

  # Same as add_item_error, named for the lookups that return it: `errors.add` hands
  # back an ActiveModel::Error, and callers here dereference the result as a record.
  alias reject add_item_error
end
