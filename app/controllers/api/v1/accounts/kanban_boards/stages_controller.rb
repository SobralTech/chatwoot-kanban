class Api::V1::Accounts::KanbanBoards::StagesController < Api::V1::Accounts::BaseController
  before_action :fetch_kanban_board
  before_action :authorize_kanban_board_update
  before_action :fetch_kanban_stage, only: [:update, :destroy, :reorder]

  def create
    KanbanStage.transaction do
      KanbanStage.normalize_positions_for_board!(@kanban_board)

      @kanban_board.kanban_stages.active.ordered.to_a.reverse_each do |stage|
        stage.update!(position: stage.position + 1)
      end

      @kanban_stage = @kanban_board.kanban_stages.create!(
        kanban_stage_params.except(:position).merge(account: Current.account, position: 1)
      )

      KanbanStage.normalize_positions_for_board!(@kanban_board)
      @kanban_stage.reload
    end

    dispatch_kanban_stage_event(Events::Types::KANBAN_STAGE_CREATED)
  end

  def update
    if deactivating_stage_with_active_cards?
      render_stage_not_empty_error
      return
    end

    @kanban_stage.update!(kanban_stage_params)
    dispatch_kanban_stage_event(Events::Types::KANBAN_STAGE_UPDATED)
  end

  def reorder
    KanbanStage.transaction do
      KanbanStage.normalize_positions_for_board!(@kanban_board)
      @kanban_stage.reload

      if params[:position].present?
        move_stage_to_position
      elsif %w[left right].include?(params[:direction])
        sibling_stage = sibling_stage_for_reorder
        swap_positions(@kanban_stage, sibling_stage) if sibling_stage
      end

      KanbanStage.normalize_positions_for_board!(@kanban_board)
      @kanban_stage.reload
    end

    dispatch_kanban_stage_event(Events::Types::KANBAN_STAGE_REORDERED)
    render :update
  end

  def destroy
    if stage_has_active_cards?
      render_stage_not_empty_error
      return
    end

    @kanban_stage.update!(active: false)
    dispatch_kanban_stage_event(Events::Types::KANBAN_STAGE_DELETED)
    head :no_content
  end

  private

  def fetch_kanban_board
    @kanban_board = policy_scope(KanbanBoard).find(params[:kanban_board_id])
  end

  def authorize_kanban_board_update
    authorize @kanban_board, :update?
  end

  def fetch_kanban_stage
    @kanban_stage = @kanban_board.kanban_stages.active.find(params[:id])
  end

  def kanban_stage_params
    params.require(:stage).permit(:name, :position, :active, :color)
  end

  def deactivating_stage_with_active_cards?
    return false unless kanban_stage_params.key?(:active)
    return false if ActiveModel::Type::Boolean.new.cast(kanban_stage_params[:active])

    stage_has_active_cards?
  end

  def stage_has_active_cards?
    @kanban_stage.kanban_cards.active.exists?
  end

  def render_stage_not_empty_error
    render json: { error: 'Kanban stage must be empty before it can be removed. Active cards are still assigned to this stage.' },
           status: :unprocessable_content
  end

  def dispatch_kanban_stage_event(event_name)
    Rails.configuration.dispatcher.dispatch(
      event_name,
      Time.zone.now,
      account_id: @kanban_stage.account_id,
      board_id: @kanban_stage.kanban_board_id,
      stage_id: @kanban_stage.id
    )
  end

  def sibling_stage_for_reorder
    ordered_stages = @kanban_board.kanban_stages.active.ordered.to_a
    stage_index = ordered_stages.index(@kanban_stage)
    offset = params[:direction] == 'left' ? -1 : 1

    ordered_stages[stage_index + offset] if stage_index && (stage_index + offset).between?(0, ordered_stages.length - 1)
  end

  def swap_positions(stage, sibling_stage)
    KanbanStage.transaction do
      stage_position = stage.position
      stage.update!(position: sibling_stage.position)
      sibling_stage.update!(position: stage_position)
    end
  end

  def move_stage_to_position
    ordered_stages = @kanban_board.kanban_stages.active.ordered.to_a
    current_index = ordered_stages.index(@kanban_stage)
    return unless current_index

    target_position = params[:position].to_i
    clamped_index = (target_position - 1).clamp(0, ordered_stages.length - 1)
    return if clamped_index == current_index

    ordered_stages.delete_at(current_index)
    ordered_stages.insert(clamped_index, @kanban_stage)

    ordered_stages.each_with_index do |stage, index|
      next if stage.position == index + 1

      stage.update!(position: index + 1)
    end
  end
end
