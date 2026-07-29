class Api::V1::Accounts::KanbanBoards::ReasonsController < Api::V1::Accounts::BaseController
  before_action :fetch_kanban_board
  before_action :authorize_kanban_board_update
  before_action :fetch_kanban_reason, only: [:update, :destroy]

  def index
    @kanban_reasons = @kanban_board.kanban_reasons.active.ordered
  end

  def create
    @kanban_reason = @kanban_board.kanban_reasons.create!(
      reason_params.merge(account: Current.account, position: next_position)
    )
    dispatch_board_updated_event
  end

  def update
    @kanban_reason.update!(reason_params)
    dispatch_board_updated_event
  end

  def destroy
    @kanban_reason.update!(active: false)
    dispatch_board_updated_event
    head :no_content
  end

  private

  def fetch_kanban_board
    @kanban_board = policy_scope(KanbanBoard).find(params[:kanban_board_id])
  end

  def authorize_kanban_board_update
    authorize @kanban_board, :update?
  end

  def fetch_kanban_reason
    @kanban_reason = @kanban_board.kanban_reasons.active.find(params[:id])
  end

  def reason_params
    params.require(:reason).permit(:title, :description, :reason_type)
  end

  def next_position
    @kanban_board.kanban_reasons.active.maximum(:position).to_i + 1
  end

  def dispatch_board_updated_event
    Rails.configuration.dispatcher.dispatch(
      Events::Types::KANBAN_BOARD_UPDATED,
      Time.zone.now,
      account_id: @kanban_board.account_id,
      board_id: @kanban_board.id
    )
  end
end
