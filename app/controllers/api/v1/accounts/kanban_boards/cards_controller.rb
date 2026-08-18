class Api::V1::Accounts::KanbanBoards::CardsController < Api::V1::Accounts::BaseController # rubocop:disable Metrics/ClassLength
  CardSnapshot = Data.define(:stage, :priority, :due_at, :labels)

  before_action :fetch_kanban_board
  before_action :authorize_kanban_board_show
  before_action :fetch_manual_card_records, only: [:create_manual]
  before_action :reject_terminal_stage_card_creation, only: [:create_manual]
  before_action :fetch_kanban_card, only: [:show, :update, :destroy, :reorder, :reopen]
  before_action :authorize_mutation_target, only: [:show, :update, :destroy, :reorder, :reopen]
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

  def reopen
    target_stage = reopen_target_stage
    return render_no_reopen_stage unless target_stage

    source_stage = @kanban_card.kanban_stage
    KanbanCard.transaction do
      @kanban_card.reorder_to_position!(kanban_stage: target_stage, position: next_card_position(target_stage))
      @kanban_card.update!(kanban_reason_id: nil)
      record_event(
        event_type: 'reopened',
        metadata: { from_stage_id: source_stage.id, to_stage_id: target_stage.id }
      )
    end

    dispatch_kanban_card_reordered_event(source_stage.id)
    render_card
  end

  def destroy
    destroy_kanban_card
  end

  private

  def fetch_kanban_board
    @kanban_board = policy_scope(KanbanBoard).find(params[:kanban_board_id])
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
      :kanban_stage_id, :position, :subject, :description, :starts_at, :due_at, :priority, :kanban_reason_id, labels: []
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
    transition_error = stable_card_move_params? && card_stage_transition_error(card_before_update.stage.id, @kanban_stage)
    return render json: transition_error, status: :unprocessable_content if transition_error

    invalid_label_titles = perform_kanban_card_update!(card_before_update)
    return render_unknown_labels(invalid_label_titles) if invalid_label_titles.present?

    dispatch_kanban_card_event(Events::Types::KANBAN_CARD_UPDATED)
    render_card
  end

  def perform_kanban_card_update!(card_before_update)
    invalid_label_titles = []
    source_stage_id = card_before_update.stage.id

    KanbanCard.transaction do
      if labels_param_present? && unknown_label_titles.present?
        invalid_label_titles = unknown_label_titles
        raise ActiveRecord::Rollback
      end

      move_kanban_card!(source_stage_id, @kanban_stage, card_params[:position] || target_card_position(@kanban_stage)) if stable_card_move_params?
      @kanban_card.update!(stable_card_update_params)
      @kanban_card.update_labels(label_titles) if labels_param_present?

      record_update_events(card_before_update)
    end

    invalid_label_titles
  end

  def reorder_kanban_card
    source_stage = @kanban_card.kanban_stage
    target_stage = target_card_stage_for_reorder

    transition_error = card_stage_transition_error(source_stage.id, target_stage)
    return render json: transition_error, status: :unprocessable_content if transition_error

    KanbanCard.transaction do
      move_kanban_card!(source_stage.id, target_stage, params.dig(:card, :position) || next_card_position(target_stage))
      record_stage_event(source_stage, target_stage)
    end

    dispatch_kanban_card_reordered_event(source_stage.id)
    render_card
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

  def next_card_position(kanban_stage)
    @kanban_board.kanban_cards.active.where(kanban_stage: kanban_stage).maximum(:position).to_i + 1
  end

  def target_card_position(kanban_stage)
    return @kanban_card.position if kanban_stage == @kanban_card.kanban_stage

    next_card_position(kanban_stage)
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
  def record_update_events(card_before_update)
    record_stage_event(card_before_update.stage, @kanban_stage)
    record_attribute_event('priority_changed', card_before_update.priority, @kanban_card.priority)
    record_attribute_event('due_at_changed', card_before_update.due_at, @kanban_card.due_at, time_value: true)
    KanbanCards::RecordEventService.labels_changed(
      card: @kanban_card, from: card_before_update.labels, to: card_label_titles, user: Current.user
    )
  end

  def record_stage_event(source_stage, target_stage)
    return if source_stage.id == target_stage.id

    event_type = terminal_event_type(target_stage)
    metadata = event_type ? terminal_event_metadata(target_stage) : stage_event_metadata(source_stage, target_stage)
    record_event(event_type: event_type || 'stage_changed', metadata: metadata)
  end

  def terminal_event_type(target_stage)
    return 'won' if target_stage.id == @kanban_board.won_stage_id
    return 'lost' if target_stage.id == @kanban_board.lost_stage_id

    nil
  end

  def stage_event_metadata(source_stage, target_stage)
    {
      from_stage_id: source_stage.id,
      to_stage_id: target_stage.id,
      from_stage_name: source_stage.name,
      to_stage_name: target_stage.name
    }
  end

  def terminal_event_metadata(target_stage)
    reason = @kanban_board.kanban_reasons.find_by(id: @kanban_card.kanban_reason_id)

    {
      stage_id: target_stage.id,
      reason_id: reason&.id,
      reason_title: reason&.title
    }
  end

  def record_attribute_event(event_type, from, to, time_value: false)
    return if from == to

    values = { from: from, to: to }
    values = values.transform_values { |value| value&.iso8601 } if time_value
    record_event(event_type: event_type, metadata: values)
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

  def move_kanban_card!(source_stage_id, target_stage, position)
    @kanban_card.reorder_to_position!(kanban_stage: target_stage, position: position)
    @kanban_card.update!(previous_stage_id: source_stage_id) if entering_terminal_stage?(source_stage_id, target_stage)
    apply_stage_reason_transition!(source_stage_id, target_stage)
  end

  def card_stage_transition_error(source_stage_id, target_stage)
    return direct_won_lost_transition_error(source_stage_id, target_stage) if direct_won_lost_transition?(source_stage_id, target_stage)

    stage_reason_transition_error(source_stage_id, target_stage)
  end

  def direct_won_lost_transition?(source_stage_id, target_stage)
    [
      source_stage_id == @kanban_board.won_stage_id && target_stage.id == @kanban_board.lost_stage_id,
      source_stage_id == @kanban_board.lost_stage_id && target_stage.id == @kanban_board.won_stage_id
    ].any?
  end

  def direct_won_lost_transition_error(_source_stage_id, _target_stage)
    { error: 'direct_won_lost_transition_not_allowed' }
  end

  def stage_reason_transition_error(source_stage_id, target_stage)
    return nil if target_stage.id == source_stage_id
    return nil unless target_stage.id == @kanban_board.lost_stage_id
    return nil unless @kanban_board.lost_reason_required?
    return nil if card_params[:kanban_reason_id].present?

    { error: 'lost_reason_required' }
  end

  def entering_terminal_stage?(source_stage_id, target_stage)
    return false if target_stage.id == source_stage_id

    !terminal_stage_id?(source_stage_id) && terminal_stage_id?(target_stage.id)
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

  def apply_stage_reason_transition!(source_stage_id, target_stage)
    return if target_stage.id == source_stage_id

    @kanban_card.update!(kanban_reason_id: resolve_transition_reason_id(target_stage))
  end

  def resolve_transition_reason_id(target_stage)
    reason_id = card_params[:kanban_reason_id]
    return nil if reason_id.blank?

    if target_stage.id == @kanban_board.lost_stage_id
      @kanban_board.kanban_reasons.active.lost.find(reason_id).id
    elsif target_stage.id == @kanban_board.won_stage_id
      @kanban_board.kanban_reasons.active.won.find(reason_id).id
    end
  end

  def dispatch_kanban_card_event(event_name, stage_id: @kanban_card.kanban_stage_id)
    Rails.configuration.dispatcher.dispatch(
      event_name,
      Time.zone.now,
      account_id: @kanban_card.account_id,
      board_id: @kanban_card.kanban_board_id,
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
