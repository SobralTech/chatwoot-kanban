class Api::V1::Accounts::KanbanBoards::CardsController < Api::V1::Accounts::BaseController # rubocop:disable Metrics/ClassLength
  CardSnapshot = Data.define(:stage, :priority, :due_at, :labels)

  before_action :fetch_kanban_board
  before_action :authorize_kanban_board_show
  before_action :fetch_manual_card_records, only: [:create_manual]
  before_action :reject_terminal_stage_card_creation, only: [:create_manual]
  before_action :fetch_kanban_card, only: [:show, :update, :destroy, :reorder, :move, :reopen]
  before_action :authorize_mutation_target, only: [:show, :update, :destroy, :reorder, :move, :reopen]
  before_action :fetch_kanban_stage, only: [:update]

  def show
    render_card
  end

  def create_manual
    @kanban_card = KanbanCards::CreateManualCardService.new(
      account: Current.account,
      user: Current.user,
      kanban_board: @kanban_board,
      kanban_stage: @kanban_stage,
      contact: @contact,
      inbox: @inbox,
      subject: manual_card_params[:subject],
      conversation: @conversation
    ).perform!

    render :create_manual, status: :created
  end

  def lookup
    contact = Current.account.contacts.find(params.require(:contact_id))
    @kanban_cards = @kanban_board.kanban_cards.active.includes(:conversation, :kanban_stage).where(contact: contact)
    @terminal_stage_ids = terminal_stage_ids
  end

  def update
    update_kanban_card
  end

  def reorder
    reorder_kanban_card
  end

  def move
    target_board = target_kanban_board
    return reorder if target_board.blank? || target_board == @kanban_board

    result = KanbanCards::MoveToBoardService.new(
      card: @kanban_card,
      target_board: target_board,
      target_stage_id: params[:kanban_stage_id],
      user: Current.user
    ).perform!
    return render json: { error: result.error }, status: :unprocessable_content unless result.success?

    @kanban_board = target_board
    render_card
  end

  def reopen
    target_stage = reopen_target_stage
    return render_no_reopen_stage unless target_stage

    stage_transition = card_stage_transition(target_stage)
    source_stage_id = stage_transition.source_stage.id
    KanbanCard.transaction do
      stage_transition.apply!(position: stage_transition.next_position)
      record_event(
        event_type: 'reopened',
        metadata: { from_stage_id: source_stage_id, to_stage_id: target_stage.id }
      )
    end

    dispatch_kanban_card_reordered_event(source_stage_id)
    render_card
  end

  def destroy
    destroy_kanban_card
  end

  private

  def fetch_kanban_board
    @kanban_board = policy_scope(KanbanBoard).find(params[:kanban_board_id])
  end

  def target_kanban_board
    return if params[:target_kanban_board_id].blank?

    policy_scope(KanbanBoard).active.find(params[:target_kanban_board_id])
  end

  def authorize_kanban_board_show
    authorize @kanban_board, :show?
  end

  def fetch_kanban_card
    @kanban_card = @kanban_board.kanban_cards.active.joins(:kanban_stage).merge(KanbanStage.active).find(params[:id])
  end

  def authorize_mutation_target
    authorize @kanban_card, action_name_policy
  end

  def fetch_kanban_stage
    stage_id = card_params[:kanban_stage_id]
    return @kanban_stage = @kanban_card.kanban_stage if stage_id.blank?

    @kanban_stage = @kanban_board.kanban_stages.active.find(stage_id)
  end

  def fetch_manual_card_records
    @kanban_stage = @kanban_board.kanban_stages.find(manual_card_params[:kanban_stage_id])
    @contact = Current.account.contacts.find(manual_card_params[:contact_id])
    if manual_card_params[:conversation_display_id].present?
      @conversation = Current.account.conversations.find_by!(display_id: manual_card_params[:conversation_display_id])
    end
    @inbox = @conversation&.inbox || Current.account.inboxes.find(manual_card_params[:inbox_id])
  end

  def reject_terminal_stage_card_creation
    return unless terminal_stage_id?(@kanban_stage.id)

    render json: { error: 'terminal_stage_card_creation_not_allowed' }, status: :unprocessable_content
  end

  def card_params
    params.require(:card).permit(
      :kanban_stage_id, :position, :after_card_id, :subject, :description, :starts_at, :due_at, :priority, :kanban_reason_id,
      labels: []
    )
  end

  def manual_card_params
    @manual_card_params ||= params.require(:card).permit(:kanban_stage_id, :contact_id, :inbox_id, :subject, :conversation_display_id)
  end

  def action_name_policy
    "#{action_name}?".to_sym
  end

  def update_kanban_card
    card_before_update = card_update_snapshot
    stage_transition = card_stage_transition(@kanban_stage)
    transition_error = stable_card_move_params? && stage_transition.error
    return render json: transition_error, status: :unprocessable_content if transition_error

    invalid_label_titles = perform_kanban_card_update!(card_before_update, stage_transition)
    return render_unknown_labels(invalid_label_titles) if invalid_label_titles.present?

    dispatch_kanban_card_event(Events::Types::KANBAN_CARD_UPDATED)
    render_card
  end

  def perform_kanban_card_update!(card_before_update, stage_transition)
    invalid_label_titles = []

    KanbanCard.transaction do
      if labels_param_present? && unknown_label_titles.present?
        invalid_label_titles = unknown_label_titles
        raise ActiveRecord::Rollback
      end

      stage_transition.apply!(position: card_params[:position]) if stable_card_move_params?
      @kanban_card.update!(stable_card_update_params)
      @kanban_card.update_labels(label_titles) if labels_param_present?

      record_update_events(card_before_update, stage_transition)
    end

    invalid_label_titles
  end

  def reorder_kanban_card
    stage_transition = card_stage_transition(target_card_stage_for_reorder)
    transition_error = stage_transition.error
    return render json: transition_error, status: :unprocessable_content if transition_error

    source_stage_id = stage_transition.source_stage.id
    KanbanCard.transaction do
      stage_transition.apply!(position: resolved_reorder_position(stage_transition))
      stage_transition.record_event!
    end

    dispatch_kanban_card_reordered_event(source_stage_id)
    render_card
  end

  def resolved_reorder_position(stage_transition)
    return card_params[:position] if card_params[:position].present?
    return stage_transition.next_position unless card_params.key?(:after_card_id)

    position_after_anchor(stage_transition, card_params[:after_card_id])
  end

  # A blank after_card_id means the card was dropped at the top of the stage.
  def position_after_anchor(stage_transition, after_card_id)
    return 1 if after_card_id.blank?

    target_stage = stage_transition.target_stage
    anchor = @kanban_board.kanban_cards.active.find_by(id: after_card_id, kanban_stage_id: target_stage.id)
    return stage_transition.next_position if anchor.nil?

    return anchor.position + 1 unless target_stage.id == @kanban_card.kanban_stage_id

    anchor.position + (anchor.position > @kanban_card.position ? 0 : 1)
  end

  def destroy_kanban_card
    stage_id = @kanban_card.kanban_stage_id
    KanbanCard.transaction do
      @kanban_card.deactivate_and_normalize!
      KanbanCards::RecordEventService.card_deleted(card: @kanban_card, user: Current.user, metadata: { stage_id: stage_id })
    end

    dispatch_kanban_card_event(Events::Types::KANBAN_CARD_DELETED, stage_id: stage_id)
    head :no_content
  end

  def stable_card_update_params
    card_params.slice(:subject, :description, :starts_at, :due_at, :priority)
  end

  def card_label_titles
    @kanban_card.label_list.to_a
  end

  def card_update_snapshot
    CardSnapshot.new(
      stage: @kanban_card.kanban_stage,
      priority: @kanban_card.priority,
      due_at: @kanban_card.due_at,
      labels: card_label_titles
    )
  end

  # Every recorder below no-ops when the value did not move, so the params do not
  # need a second round of guards here.
  def record_update_events(card_before_update, stage_transition)
    stage_transition.record_event!
    record_attribute_event('priority_changed', card_before_update.priority, @kanban_card.priority)
    record_attribute_event('due_at_changed', card_before_update.due_at, @kanban_card.due_at)
    KanbanCards::RecordEventService.labels_changed(
      card: @kanban_card, from: card_before_update.labels, to: card_label_titles, user: Current.user
    )
  end

  def record_attribute_event(event_type, from, to)
    KanbanCards::RecordEventService.attribute_changed(
      card: @kanban_card, event_type: event_type, from: from, to: to, user: Current.user
    )
  end

  def record_event(event_type:, metadata: {})
    KanbanCards::RecordEventService.call(
      card: @kanban_card,
      event_type: event_type,
      user: Current.user,
      metadata: metadata
    )
  end

  def labels_param_present?
    params.require(:card).key?(:labels)
  end

  def label_titles
    @label_titles ||= Array(card_params[:labels]).uniq
  end

  def account_label_titles
    @account_label_titles ||= Current.account.labels.where(title: label_titles).pluck(:title)
  end

  def unknown_label_titles
    @unknown_label_titles ||= label_titles - account_label_titles
  end

  def render_unknown_labels(label_titles)
    render json: { error: "Unknown labels: #{label_titles.join(', ')}" }, status: :unprocessable_entity
  end

  def stable_card_move_params?
    card_params[:kanban_stage_id].present? || card_params[:position].present?
  end

  def target_card_stage_for_reorder
    stage_id = params.dig(:card, :kanban_stage_id)
    return @kanban_card.kanban_stage if stage_id.blank?

    @kanban_board.kanban_stages.active.find(stage_id)
  end

  def terminal_stage_id?(stage_id)
    terminal_stage_ids.include?(stage_id)
  end

  def reopen_target_stage
    previous_stage = @kanban_board.kanban_stages.active.find_by(id: @kanban_card.previous_stage_id)
    return previous_stage if previous_stage && !terminal_stage_id?(previous_stage.id)

    regular_stages = @kanban_board.kanban_stages.active
    regular_stages = regular_stages.where.not(id: terminal_stage_ids) if terminal_stage_ids.present?
    regular_stages.order(position: :desc, id: :desc).first
  end

  def terminal_stage_ids
    @terminal_stage_ids ||= KanbanStage.special_stage_ids(@kanban_board)
  end

  def render_no_reopen_stage
    render json: { error: 'no_active_regular_stage_available' }, status: :unprocessable_content
  end

  def card_stage_transition(target_stage)
    KanbanCards::StageTransition.new(
      kanban_board: @kanban_board,
      kanban_card: @kanban_card,
      target_stage: target_stage,
      kanban_reason_id: transition_reason_id,
      user: Current.user
    )
  end

  def transition_reason_id
    return if params[:card].blank?

    card_params[:kanban_reason_id]
  end

  def dispatch_kanban_card_event(event_name, board_id: @kanban_card.kanban_board_id, stage_id: @kanban_card.kanban_stage_id)
    Rails.configuration.dispatcher.dispatch(
      event_name,
      Time.zone.now,
      account_id: @kanban_card.account_id,
      board_id: board_id,
      stage_id: stage_id,
      card_id: @kanban_card.id,
      conversation_id: @kanban_card.conversation_id
    )
  end

  def dispatch_kanban_card_reordered_event(source_stage_id)
    Rails.configuration.dispatcher.dispatch(
      Events::Types::KANBAN_CARD_REORDERED,
      Time.zone.now,
      account_id: @kanban_card.account_id,
      board_id: @kanban_card.kanban_board_id,
      card_id: @kanban_card.id,
      conversation_id: @kanban_card.conversation_id,
      source_stage_id: source_stage_id,
      target_stage_id: @kanban_card.kanban_stage_id
    )
  end

  def render_card
    last_movement_event = @kanban_card.kanban_card_events.movements.recent_first.first

    render partial: 'api/v1/accounts/kanban_boards/card', formats: [:json], locals: {
      card: @kanban_card,
      stable_card: true,
      last_movement_event: last_movement_event
    }
  end
end
