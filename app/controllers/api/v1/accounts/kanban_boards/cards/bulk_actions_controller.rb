class Api::V1::Accounts::KanbanBoards::Cards::BulkActionsController < Api::V1::Accounts::BaseController
  before_action :fetch_kanban_board
  before_action :authorize_kanban_board_show

  def create
    result = KanbanCards::BulkActionService.new(
      user: Current.user,
      kanban_board: @kanban_board,
      operation: bulk_action_params[:operation],
      card_ids: bulk_action_params[:card_ids],
      payload: bulk_action_params[:payload] || {}
    ).perform!

    render json: { succeeded: result.succeeded, failed: result.failed }
  rescue KanbanCards::BulkActionRequest::Error => e
    render json: { error: e.code }, status: :unprocessable_content
  end

  private

  def fetch_kanban_board
    @kanban_board = policy_scope(KanbanBoard).find(params[:kanban_board_id])
  end

  def authorize_kanban_board_show
    authorize @kanban_board, :show?
  end

  # `action` is reserved: Rails merges the routing action over any body param of the
  # same name, so the requested operation has to travel under its own key.
  def bulk_action_params
    @bulk_action_params ||= params.permit(:operation, card_ids: [], payload: {})
  end
end
