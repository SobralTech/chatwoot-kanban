class Api::V1::Accounts::KanbanBoardsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_kanban_board, only: [:show, :update, :destroy]

  def index
    @kanban_boards = policy_scope(KanbanBoard).ordered
  end

  def show
    @kanban_stages = @kanban_board.kanban_stages.active.ordered
    fetch_stage_card_results
  end

  def create
    @kanban_board = KanbanBoard.create!(kanban_board_params.merge(account: Current.account))
  end

  def update
    @kanban_board.update!(kanban_board_params)
    dispatch_kanban_board_event(Events::Types::KANBAN_BOARD_UPDATED)
  end

  def destroy
    @kanban_board.update!(active: false)
    head :no_content
  end

  private

  def fetch_kanban_board
    @kanban_board = policy_scope(KanbanBoard).find(params[:id])
  end

  def kanban_board_params
    params.require(:kanban_board).permit(:name, :description, :position, :active, :auto_create_cards_from_conversations)
  end

  def fetch_stage_card_results
    @stage_card_limit = KanbanCards::VisibleStageCardsQuery::DEFAULT_LIMIT
    @stage_card_results = @kanban_stages.index_with do |kanban_stage|
      KanbanCards::VisibleStageCardsQuery.new(
        account: Current.account,
        user: Current.user,
        kanban_board: @kanban_board,
        kanban_stage: kanban_stage,
        limit: @stage_card_limit,
        visible_inbox_ids: board_list_inbox_ids,
        visible_team_ids: board_list_team_ids,
        account_user: Current.account_user
      ).call
    end
  end

  def dispatch_kanban_board_event(event_name)
    Rails.configuration.dispatcher.dispatch(event_name, Time.zone.now, account_id: @kanban_board.account_id, board_id: @kanban_board.id)
  end

  def board_list_inbox_ids
    return [] if Current.user.is_a?(AgentBot)

    @board_list_inbox_ids ||= Current.user.inboxes.where(account_id: Current.account.id).pluck(:id)
  end

  def board_list_team_ids
    return [] if Current.user.is_a?(AgentBot)

    @board_list_team_ids ||= Current.user.teams.where(account_id: Current.account.id).pluck(:id)
  end
end
