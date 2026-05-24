class Api::V1::Accounts::KanbanBoards::StagesController < Api::V1::Accounts::BaseController
  before_action :fetch_kanban_board
  before_action :authorize_kanban_board_update
  before_action :fetch_kanban_stage, only: [:update, :destroy, :reorder]

  def create
    @kanban_stage = @kanban_board.kanban_stages.create!(kanban_stage_params.merge(account: Current.account))
  end

  def update
    @kanban_stage.update!(kanban_stage_params)
  end

  def reorder
    return render :update unless %w[left right].include?(params[:direction])

    KanbanStage.transaction do
      KanbanStage.normalize_positions_for_board!(@kanban_board)
      @kanban_stage.reload

      sibling_stage = sibling_stage_for_reorder
      swap_positions(@kanban_stage, sibling_stage) if sibling_stage

      KanbanStage.normalize_positions_for_board!(@kanban_board)
      @kanban_stage.reload
    end

    render :update
  end

  def destroy
    if @kanban_stage.conversation_kanban_states.exists?
      render json: { error: 'Kanban stage must be empty before it can be removed.' }, status: :unprocessable_content
      return
    end

    @kanban_stage.update!(active: false)
    head :no_content
  end

  private

  def fetch_kanban_board
    @kanban_board = KanbanBoard.where(account_id: Current.account.id).active.find(params[:kanban_board_id])
  end

  def authorize_kanban_board_update
    authorize @kanban_board, :update?
  end

  def fetch_kanban_stage
    @kanban_stage = @kanban_board.kanban_stages.active.find(params[:id])
  end

  def kanban_stage_params
    params.require(:stage).permit(:name, :position, :active)
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
end
