class ActionService
  include EmailHelper

  def initialize(conversation)
    @conversation = conversation.reload
    @account = @conversation.account
  end

  def mute_conversation(_params)
    @conversation.mute!
  end

  def snooze_conversation(_params)
    @conversation.snoozed!
  end

  def resolve_conversation(_params)
    @conversation.resolved!
  end

  def open_conversation(_params)
    @conversation.open!
  end

  def pending_conversation(_params)
    @conversation.pending!
  end

  def change_status(status)
    @conversation.update!(status: status[0])
  end

  def change_priority(priority)
    @conversation.update!(priority: (priority[0] == 'nil' ? nil : priority[0]))
  end

  def add_label(labels)
    return if labels.empty?

    @conversation.reload.add_labels(labels)
  end

  def assign_agent(agent_ids = [])
    return @conversation.update!(assignee_id: nil) if agent_ids[0] == 'nil'

    agent_ids = [last_responding_agent_id] if agent_ids[0] == 'last_responding_agent'
    return unless agent_belongs_to_inbox?(agent_ids)

    @agent = @account.users.find_by(id: agent_ids)
    return unless @agent.present? && @agent.confirmed?

    @conversation.update!(assignee_id: @agent.id)
  end

  def remove_label(labels)
    return if labels.empty?

    labels = @conversation.label_list - labels
    @conversation.update(label_list: labels)
  end

  def assign_team(team_ids = [])
    # Keep nil/0 handling for existing automation and macro payloads.
    should_unassign = team_ids.blank? || %w[nil 0].include?(team_ids[0].to_s)
    return @conversation.update!(team_id: nil) if should_unassign

    # check if team belongs to account only if team_id is present
    # if team_id is nil, then it means that the team is being unassigned
    return unless !team_ids[0].nil? && team_belongs_to_account?(team_ids)

    @conversation.update!(team_id: team_ids[0])
  end

  def remove_assigned_agent(_params)
    @conversation.update!(assignee_id: nil)
  end

  def remove_assigned_team(_params)
    @conversation.update!(team_id: nil)
  end

  def send_email_transcript(emails)
    return unless @account.email_transcript_enabled?

    emails = emails[0].gsub(/\s+/, '').split(',')

    emails.each do |email|
      break unless @account.within_email_rate_limit?

      email = parse_email_variables(@conversation, email)
      ConversationReplyMailer.with(account: @conversation.account).conversation_transcript(@conversation, email)&.deliver_later
      @account.increment_email_sent_count
    end
  end

  private

  def last_responding_agent_id
    @conversation.messages.outgoing.where(sender_type: 'User', private: false).last&.sender_id
  end

  def agent_belongs_to_inbox?(agent_ids)
    member_ids = @conversation.inbox.members.pluck(:user_id)
    assignable_agent_ids = member_ids + @account.administrators.ids

    assignable_agent_ids.include?(agent_ids[0])
  end

  def team_belongs_to_account?(team_ids)
    @account.team_ids.include?(team_ids[0])
  end

  def conversation_a_tweet?
    return false if @conversation.additional_attributes.blank?

    @conversation.additional_attributes['type'] == 'tweet'
  end
end

module ActionServiceKanbanActions
  def add_to_kanban_board(params)
    kanban_board, kanban_stage = kanban_target(params, action_name: 'add_to_kanban_board')
    return if kanban_board.blank? || kanban_stage.blank? || terminal_stage?(kanban_board, kanban_stage)
    if KanbanCard.conversation.exists?(kanban_board: kanban_board, conversation_id: @conversation.id)
      return log_kanban_skip('add_to_kanban_board', 'conversation already has a card', kanban_board)
    end

    KanbanCards::CreateFromConversationService.new(
      account: @account,
      user: nil,
      conversation: @conversation,
      kanban_board: kanban_board,
      kanban_stage: kanban_stage,
      subject: nil
    ).perform!
  rescue ActiveRecord::RecordInvalid => e
    log_kanban_failure('add_to_kanban_board', e)
  rescue StandardError => e
    capture_kanban_failure('add_to_kanban_board', e)
  end

  def move_kanban_card(params)
    kanban_board, kanban_stage = kanban_target(params, action_name: 'move_kanban_card')
    return if kanban_board.blank? || kanban_stage.blank? || kanban_move_blocked?(kanban_board, kanban_stage)

    kanban_card = active_kanban_card_for(kanban_board)
    return log_kanban_skip('move_kanban_card', 'conversation has no active card', kanban_board) if kanban_card.blank?

    move_kanban_card!(kanban_board, kanban_card, kanban_stage)
  rescue ActiveRecord::RecordInvalid => e
    log_kanban_failure('move_kanban_card', e)
  rescue StandardError => e
    capture_kanban_failure('move_kanban_card', e)
  end

  def assign_kanban_card(params)
    action_params = normalized_kanban_params(params)
    kanban_board, = kanban_target(params, action_name: 'assign_kanban_card', stage_required: false)
    return if kanban_board.blank?

    kanban_card = active_kanban_card_for(kanban_board)
    return log_kanban_skip('assign_kanban_card', 'conversation has no active card', kanban_board) if kanban_card.blank?

    agent_ids = Array(action_params[:agent_ids]).filter_map(&:presence).map(&:to_i).uniq
    return unless assignable_kanban_agents?(kanban_board, agent_ids)

    assign_kanban_card!(kanban_card, agent_ids)
  rescue ActiveRecord::RecordInvalid => e
    log_kanban_failure('assign_kanban_card', e)
  rescue StandardError => e
    capture_kanban_failure('assign_kanban_card', e)
  end
end

module ActionServiceKanbanTargets
  private

  def normalized_kanban_params(params)
    value = params.is_a?(Array) ? params.first : params
    return {} unless value.respond_to?(:to_h)

    value.to_h.with_indifferent_access
  end

  def kanban_target(params, action_name:, stage_required: true)
    action_params = normalized_kanban_params(params)
    board_id = action_params[:kanban_board_id]
    kanban_board = KanbanBoard.active.find_by(account: @account, id: board_id)
    return log_missing_kanban_target(action_name, board_id) if kanban_board.blank?
    return [kanban_board, nil] unless stage_required

    stage_id = action_params[:kanban_stage_id]
    kanban_stage = kanban_board.kanban_stages.active.find_by(id: stage_id)
    return log_missing_kanban_target(action_name, board_id, kanban_board, stage_id) if kanban_stage.blank?

    [kanban_board, kanban_stage]
  end

  def log_missing_kanban_target(action_name, board_id, kanban_board = nil, stage_id = nil)
    reason = kanban_board ? 'stage is missing or inactive' : 'board is missing or inactive'
    log_kanban_skip(action_name, reason, kanban_board, board_id: board_id, stage_id: stage_id)
    [nil, nil]
  end

  def terminal_stage?(kanban_board, kanban_stage)
    return false unless KanbanStage.special_stage_ids(kanban_board).include?(kanban_stage.id)

    log_kanban_skip('add_to_kanban_board', 'terminal stages cannot receive new cards', kanban_board,
                    stage_id: kanban_stage.id)
    true
  end

  def kanban_move_blocked?(kanban_board, kanban_stage)
    if kanban_stage.id == kanban_board.won_stage_id
      log_kanban_skip('move_kanban_card', 'won stage transitions are not automated', kanban_board)
      return true
    end
    if kanban_stage.id == kanban_board.lost_stage_id && kanban_board.lost_reason_required?
      log_kanban_skip('move_kanban_card', 'lost stage requires a reason', kanban_board)
      return true
    end

    false
  end

  def active_kanban_card_for(kanban_board)
    conversation_card = KanbanCard.active.where(kanban_board: kanban_board, conversation_id: @conversation.id).first
    return conversation_card if conversation_card.present?

    KanbanCard.active_non_terminal_for(kanban_board, @conversation.contact_id).ordered.first
  end

  def kanban_action_user
    @user if instance_variable_defined?(:@user)
  end
end

module ActionServiceKanbanTransitions
  private

  def move_kanban_card!(kanban_board, kanban_card, kanban_stage)
    transition = KanbanCards::StageTransition.new(
      kanban_board: kanban_board,
      kanban_card: kanban_card,
      target_stage: kanban_stage,
      user: kanban_action_user
    )
    transition_error = transition.error
    return log_kanban_skip('move_kanban_card', transition_error[:error], kanban_board) if transition_error

    source_stage_id = transition.source_stage.id
    KanbanCard.transaction do
      transition.apply!
      transition.record_event!
    end
    dispatch_kanban_card_reordered_event(kanban_card, source_stage_id) if source_stage_id != kanban_stage.id
  end

  def assignable_kanban_agents?(kanban_board, agent_ids)
    assignable_agent_ids = kanban_board.assignable_users.where(id: agent_ids).pluck(:id)
    return true if assignable_agent_ids.sort == agent_ids.sort

    log_kanban_skip('assign_kanban_card', 'one or more agents are not assignable on the board', kanban_board)
    false
  end

  def assign_kanban_card!(kanban_card, agent_ids)
    previous_agent_ids = kanban_card.kanban_card_assignees.pluck(:user_id)
    kanban_card.update_assignees!(agent_ids)
    KanbanCards::RecordEventService.assignees_changed(
      card: kanban_card,
      from: previous_agent_ids,
      to: agent_ids,
      user: kanban_action_user
    )
    dispatch_kanban_card_event(Events::Types::KANBAN_CARD_UPDATED, kanban_card)
  end
end

module ActionServiceKanbanEvents
  private

  def dispatch_kanban_card_event(event_name, kanban_card)
    Rails.configuration.dispatcher.dispatch(
      event_name,
      Time.zone.now,
      account_id: kanban_card.account_id,
      board_id: kanban_card.kanban_board_id,
      stage_id: kanban_card.kanban_stage_id,
      card_id: kanban_card.id,
      conversation_id: kanban_card.conversation_id
    )
  end

  def dispatch_kanban_card_reordered_event(kanban_card, source_stage_id)
    Rails.configuration.dispatcher.dispatch(
      Events::Types::KANBAN_CARD_REORDERED,
      Time.zone.now,
      account_id: kanban_card.account_id,
      board_id: kanban_card.kanban_board_id,
      card_id: kanban_card.id,
      conversation_id: kanban_card.conversation_id,
      source_stage_id: source_stage_id,
      target_stage_id: kanban_card.kanban_stage_id
    )
  end

  def log_kanban_skip(action_name, reason, kanban_board = nil, board_id: nil, stage_id: nil)
    board_id ||= kanban_board&.id
    Rails.logger.info("Kanban action #{action_name} skipped: #{reason} (account=#{@account.id}, board=#{board_id}, stage=#{stage_id})")
    nil
  end

  def log_kanban_failure(action_name, error)
    Rails.logger.warn("Kanban action #{action_name} failed validation: #{error.message}")
  end

  def capture_kanban_failure(action_name, error)
    Rails.logger.error("Kanban action #{action_name} failed: #{error.class}: #{error.message}")
    ChatwootExceptionTracker.new(error, account: @account).capture_exception
  end
end

ActionService.include ActionServiceKanbanTargets
ActionService.include ActionServiceKanbanTransitions
ActionService.include ActionServiceKanbanEvents
ActionService.include ActionServiceKanbanActions
ActionService.include_mod_with('ActionService')
