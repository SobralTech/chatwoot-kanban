class Api::V1::Accounts::KanbanBoards::SummaryController < Api::V1::Accounts::BaseController
  include KanbanCardFilterParams

  before_action :fetch_kanban_board
  before_action :authorize_kanban_board_show

  def show
    @summary = KanbanBoards::SummaryQuery.new(
      account: Current.account,
      user: Current.user,
      kanban_board: @kanban_board,
      visible_inbox_ids: board_visible_inbox_ids,
      visible_team_ids: board_visible_team_ids,
      account_user: Current.account_user,
      **kanban_card_filter_params.except(:terminal_period)
    ).call
  end

  private

  def fetch_kanban_board
    @kanban_board = policy_scope(KanbanBoard).find(params[:kanban_board_id])
  end

  def authorize_kanban_board_show
    authorize @kanban_board, :show?
  end

  def board_visible_inbox_ids
    return [] if Current.user.is_a?(AgentBot)

    @board_visible_inbox_ids ||= Current.user.inboxes.where(account_id: Current.account.id).pluck(:id)
  end

  def board_visible_team_ids
    return [] if Current.user.is_a?(AgentBot)

    @board_visible_team_ids ||= Current.user.teams.where(account_id: Current.account.id).pluck(:id)
  end
end
