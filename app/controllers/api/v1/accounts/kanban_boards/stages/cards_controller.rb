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
      cursor: params[:cursor],
      filtered_inbox_ids: sanitized_inbox_filter_ids,
      filtered_assignee_ids: sanitized_assignee_filter_ids
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

  def sanitized_inbox_filter_ids
    return @sanitized_inbox_filter_ids if defined?(@sanitized_inbox_filter_ids)

    inbox_ids = Array(params[:inbox_ids]).filter_map(&:presence).map(&:to_i).uniq
    @sanitized_inbox_filter_ids =
      if inbox_ids.blank?
        nil
      else
        validate_account_inbox_ids!(inbox_ids)
        inbox_ids & board_filterable_inbox_ids(inbox_ids)
      end
  end

  def sanitized_assignee_filter_ids
    return @sanitized_assignee_filter_ids if defined?(@sanitized_assignee_filter_ids)

    assignee_ids = Array(params[:assignee_ids]).filter_map(&:presence).map(&:to_i).uniq
    @sanitized_assignee_filter_ids =
      if assignee_ids.blank?
        nil
      else
        validate_account_user_ids!(assignee_ids)
        assignee_ids
      end
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
end
