class Api::V1::Accounts::KanbanBoardsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_kanban_board, only: [:show, :update, :destroy]

  def index
    @kanban_boards = policy_scope(KanbanBoard).ordered.to_a
    fetch_overview_data
  end

  def show
    sanitized_inbox_filter_ids
    sanitized_assignee_filter_ids
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

  def fetch_overview_data
    board_ids = @kanban_boards.map(&:id)

    @overview_stages_by_board_id = {}
    @overview_cards_count_by_board_id = {}
    @overview_cards_count_by_stage_id = {}
    @overview_visible_users_by_board_id = {}
    @overview_allowed_inboxes_by_board_id = {}

    return if board_ids.blank?

    overview_stages = active_overview_stages(board_ids)
    stage_ids = overview_stages.map(&:id)

    @overview_stages_by_board_id = overview_stages.group_by(&:kanban_board_id)
    @overview_cards_count_by_board_id = active_kanban_card_counts(:kanban_board_id, kanban_board_id: board_ids)
    @overview_cards_count_by_stage_id = active_kanban_card_counts(:kanban_stage_id, kanban_stage_id: stage_ids)
    @overview_visible_users_by_board_id = overview_visible_users_by_board_id(board_ids)
    @overview_allowed_inboxes_by_board_id = overview_allowed_inboxes_by_board_id(board_ids)
  end

  def active_overview_stages(board_ids)
    KanbanStage.where(account_id: Current.account.id, kanban_board_id: board_ids)
               .active.ordered.to_a
  end

  def active_kanban_card_counts(group_key, filters)
    KanbanCard.active
              .where(account_id: Current.account.id)
              .where(filters)
              .group(group_key).count
  end

  def overview_visible_users_by_board_id(board_ids)
    KanbanBoardMember.includes(user: { avatar_attachment: :blob })
                     .where(account_id: Current.account.id, kanban_board_id: board_ids)
                     .order(:user_id)
                     .group_by(&:kanban_board_id)
                     .transform_values { |members| members.map(&:user) }
  end

  def overview_allowed_inboxes_by_board_id(board_ids)
    KanbanBoardInbox.includes(:inbox)
                    .where(account_id: Current.account.id, kanban_board_id: board_ids)
                    .order(:inbox_id)
                    .group_by(&:kanban_board_id)
                    .transform_values { |board_inboxes| board_inboxes.map(&:inbox) }
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
        filtered_assignee_ids: sanitized_assignee_filter_ids,
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

  def sanitized_assignee_filter_ids
    return @sanitized_assignee_filter_ids if defined?(@sanitized_assignee_filter_ids)

    assignee_ids = normalized_assignee_filter_ids
    @sanitized_assignee_filter_ids =
      if assignee_ids.blank?
        nil
      else
        validate_account_user_ids!(assignee_ids)
        assignee_ids
      end
  end

  def normalized_assignee_filter_ids
    Array(params[:assignee_ids]).filter_map(&:presence).map(&:to_i).uniq
  end

  def validate_account_inbox_ids!(inbox_ids)
    return if inbox_ids.blank?

    valid_inbox_count = Inbox.where(account_id: Current.account.id, id: inbox_ids).count
    return if valid_inbox_count == inbox_ids.length

    raise ActiveRecord::RecordInvalid, @kanban_board
  end

  def validate_account_user_ids!(user_ids)
    return if user_ids.blank?

    valid_user_count = Current.account.account_users.where(user_id: user_ids).count
    return if valid_user_count == user_ids.length

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
