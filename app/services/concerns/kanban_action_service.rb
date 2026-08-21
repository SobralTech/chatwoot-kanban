# The Kanban actions available to both Automation Rules and Macros. They live on the
# shared ActionService base so a macro gets them for free, and in a concern so
# action_service.rb stays the list of conversation actions.
#
# Everything here fails quietly and logs: a rule that names a deleted board should skip
# its Kanban action and carry on to the next one, not abort the whole rule.
module KanbanActionService
  extend ActiveSupport::Concern

  def add_to_kanban_board(params)
    target = kanban_target('add_to_kanban_board', params)
    return unless target.resolve
    return target.skip('terminal stages cannot receive new cards') if target.terminal_stage?

    KanbanCards::CreateFromConversationService.new(
      account: @account,
      user: nil,
      conversation: @conversation,
      kanban_board: target.board,
      kanban_stage: target.stage,
      subject: nil
    ).perform!
  rescue ActiveRecord::RecordInvalid => e
    log_kanban_failure('add_to_kanban_board', e)
  rescue StandardError => e
    capture_kanban_failure('add_to_kanban_board', e)
  end

  def move_kanban_card(params)
    target = kanban_target('move_kanban_card', params)
    return unless target.resolve

    blocked = target.move_blocked_reason
    return target.skip(blocked) if blocked
    return target.skip('conversation has no active card') if target.active_card.blank?

    move_kanban_card!(target)
  rescue ActiveRecord::RecordInvalid => e
    log_kanban_failure('move_kanban_card', e)
  rescue StandardError => e
    capture_kanban_failure('move_kanban_card', e)
  end

  def assign_kanban_card(params)
    target = kanban_target('assign_kanban_card', params)
    return unless target.resolve(stage_required: false)
    return target.skip('conversation has no active card') if target.active_card.blank?

    agent_ids = target.agent_ids
    unassignable = target.unassignable_agents(agent_ids)
    return target.skip("agents are not assignable on the board: #{unassignable.join(', ')}") if unassignable.any?

    assign_kanban_card!(target.active_card, agent_ids)
  rescue ActiveRecord::RecordInvalid => e
    log_kanban_failure('assign_kanban_card', e)
  rescue StandardError => e
    capture_kanban_failure('assign_kanban_card', e)
  end

  private

  def kanban_target(action_name, params)
    KanbanCards::ActionTarget.new(conversation: @conversation, action_name: action_name, params: params)
  end

  def move_kanban_card!(target)
    card = target.active_card
    transition = KanbanCards::StageTransition.new(
      kanban_board: target.board,
      kanban_card: card,
      target_stage: target.stage,
      user: @user
    )
    error = transition.error
    return target.skip(error[:error]) if error

    source_stage_id = transition.source_stage.id
    KanbanCard.transaction do
      transition.apply!
      transition.record_event!
    end
    KanbanCards::EventDispatcher.card_reordered(card, source_stage_id: source_stage_id) if source_stage_id != target.stage.id
  end

  def assign_kanban_card!(card, agent_ids)
    previous_agent_ids = card.kanban_card_assignees.pluck(:user_id)
    card.update_assignees!(agent_ids)
    KanbanCards::RecordEventService.assignees_changed(card: card, from: previous_agent_ids, to: agent_ids, user: @user)
    KanbanCards::EventDispatcher.card_event(Events::Types::KANBAN_CARD_UPDATED, card)
  end

  def log_kanban_failure(action_name, error)
    Rails.logger.warn("Kanban action #{action_name} failed validation: #{error.message}")
  end

  def capture_kanban_failure(action_name, error)
    Rails.logger.error("Kanban action #{action_name} failed: #{error.class}: #{error.message}")
    ChatwootExceptionTracker.new(error, account: @account).capture_exception
  end
end
