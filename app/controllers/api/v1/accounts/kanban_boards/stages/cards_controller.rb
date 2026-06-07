class Api::V1::Accounts::KanbanBoards::Stages::CardsController < Api::V1::Accounts::BaseController
  before_action :fetch_kanban_board
  before_action :authorize_kanban_board_show
  before_action :fetch_kanban_stage

  def index
    @limit = cards_limit
    @result = KanbanCards::VisibleStageCardsQuery.new(
      account: Current.account,
      user: Current.user,
      kanban_board: @kanban_board,
      kanban_stage: @kanban_stage,
      limit: @limit,
      cursor: params[:cursor]
    ).call
  rescue KanbanCards::VisibleStageCardsQuery::RefreshRequiredError
    render json: { error: 'refresh_required' }, status: :conflict
  end

  private

  def fetch_kanban_board
    @kanban_board = policy_scope(KanbanBoard).find(params[:kanban_board_id])
  end

  def authorize_kanban_board_show
    authorize @kanban_board, :show?
  end

  def fetch_kanban_stage
    @kanban_stage = @kanban_board.kanban_stages.active.find(params[:stage_id])
  end

  def cards_limit
    (params[:limit] || KanbanCards::VisibleStageCardsQuery::DEFAULT_LIMIT).to_i.clamp(
      1,
      KanbanCards::VisibleStageCardsQuery::MAX_LIMIT
    )
  end
end
