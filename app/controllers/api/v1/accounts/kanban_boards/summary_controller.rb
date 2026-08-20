class Api::V1::Accounts::KanbanBoards::SummaryController < Api::V1::Accounts::BaseController
  include KanbanCardFilterParams

  before_action :fetch_kanban_board
  before_action :authorize_kanban_board_show

  def show
    @summary = KanbanBoards::SummaryQuery.new(
      account: Current.account,
      kanban_board: @kanban_board,
      visible_cards: visible_cards_scope
    ).call
  end

  private

  def fetch_kanban_board
    @kanban_board = policy_scope(KanbanBoard).find(params[:kanban_board_id])
  end

  def authorize_kanban_board_show
    authorize @kanban_board, :show?
  end
end
