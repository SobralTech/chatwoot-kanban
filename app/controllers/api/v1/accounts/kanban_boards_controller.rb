class Api::V1::Accounts::KanbanBoardsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_kanban_board, only: [:show, :update, :destroy]

  def index
    @kanban_boards = policy_scope(KanbanBoard).ordered
  end

  def show
    sanitized_inbox_filter_ids
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
        filtered_inbox_ids: sanitized_inbox_filter_ids,
        visible_inbox_ids: board_list_inbox_ids,
        visible_team_ids: board_list_team_ids,
        account_user: Current.account_user
      ).call
    end
  end

  def sanitized_inbox_filter_ids
    return @sanitized_inbox_filter_ids if defined?(@sanitized_inbox_filter_ids)

    inbox_ids = normalized_inbox_filter_ids
    @sanitized_inbox_filter_ids =
      if inbox_ids.blank?
        nil
      else
        validate_account_inbox_ids!(inbox_ids)
        inbox_ids & board_filterable_inbox_ids(inbox_ids)
      end
  end

  def normalized_inbox_filter_ids
    Array(params[:inbox_ids]).filter_map(&:presence).map(&:to_i).uniq
  end

  def validate_account_inbox_ids!(inbox_ids)
    return if inbox_ids.blank?

    valid_inbox_count = Inbox.where(account_id: Current.account.id, id: inbox_ids).count
    return if valid_inbox_count == inbox_ids.length

    raise ActiveRecord::RecordInvalid, @kanban_board
  end

  def board_filterable_inbox_ids(inbox_ids)
    return inbox_ids if @kanban_board.all_inboxes?

    @kanban_board.kanban_board_inboxes.where(inbox_id: inbox_ids).pluck(:inbox_id)
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
