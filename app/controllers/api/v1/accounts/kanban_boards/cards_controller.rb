class Api::V1::Accounts::KanbanBoards::CardsController < Api::V1::Accounts::BaseController
  before_action :fetch_kanban_board
  before_action :authorize_kanban_board_show
  before_action :fetch_manual_card_records, only: [:create_manual]
  before_action :fetch_kanban_card, only: [:show, :update, :destroy, :reorder]
  before_action :authorize_mutation_target, only: [:show, :update, :destroy, :reorder]
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
      subject: manual_card_params[:subject]
    ).perform!

    render :create_manual, status: :created
  end

  def update
    update_kanban_card
  end

  def reorder
    reorder_kanban_card
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
    @inbox = Current.account.inboxes.find(manual_card_params[:inbox_id])
  end

  def card_params
    params.require(:card).permit(:kanban_stage_id, :position, :subject, :description, :starts_at, :due_at, labels: [])
  end

  def manual_card_params
    params.require(:card).permit(:kanban_stage_id, :contact_id, :inbox_id, :subject)
  end

  def action_name_policy
    "#{action_name}?".to_sym
  end

  def update_kanban_card
    invalid_label_titles = []

    KanbanCard.transaction do
      if labels_param_present? && unknown_label_titles.present?
        invalid_label_titles = unknown_label_titles
        raise ActiveRecord::Rollback
      end

      if stable_card_move_params?
        @kanban_card.reorder_to_position!(
          kanban_stage: @kanban_stage,
          position: card_params[:position] || target_card_position(@kanban_stage)
        )
      end
      @kanban_card.update!(stable_card_update_params)
      @kanban_card.update_labels(label_titles) if labels_param_present?
    end

    return render_unknown_labels(invalid_label_titles) if invalid_label_titles.present?

    dispatch_kanban_card_event(Events::Types::KANBAN_CARD_UPDATED)
    render_card
  end

  def reorder_kanban_card
    source_stage_id = @kanban_card.kanban_stage_id

    KanbanCard.transaction do
      @kanban_card.reorder_to_position!(
        kanban_stage: target_card_stage_for_reorder,
        position: params.dig(:card, :position) || @kanban_card.position
      )
    end

    dispatch_kanban_card_reordered_event(source_stage_id)
    render_card
  end

  def destroy_kanban_card
    stage_id = @kanban_card.kanban_stage_id
    @kanban_card.deactivate_and_normalize!

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
    card_params.slice(:subject, :description, :starts_at, :due_at)
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
    render partial: 'api/v1/accounts/kanban_boards/card', formats: [:json], locals: {
      card: @kanban_card,
      stable_card: true
    }
  end
end
