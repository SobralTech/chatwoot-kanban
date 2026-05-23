class Api::V1::Accounts::KanbanBoards::StagesController < Api::V1::Accounts::BaseController
  before_action :fetch_kanban_board
  before_action :authorize_kanban_board_update
  before_action :fetch_kanban_stage, only: [:update, :destroy]

  def create
    @kanban_stage = @kanban_board.kanban_stages.create!(kanban_stage_params.merge(account: Current.account))
  end

  def update
    @kanban_stage.update!(kanban_stage_params)
  end

  def destroy
    @kanban_stage.destroy!
    head :no_content
  end

  private

  def fetch_kanban_board
    @kanban_board = KanbanBoard.where(account_id: Current.account.id).find(params[:kanban_board_id])
  end

  def authorize_kanban_board_update
    authorize @kanban_board, :update?
  end

  def fetch_kanban_stage
    @kanban_stage = @kanban_board.kanban_stages.find(params[:id])
  end

  def kanban_stage_params
    params.require(:stage).permit(:name, :position, :active)
  end
end
