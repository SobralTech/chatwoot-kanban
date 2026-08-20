class Api::V1::Accounts::KanbanBoards::Stages::CardsController < Api::V1::Accounts::BaseController
  include KanbanCardFilterParams

  SORT_BY_VALUES = %w[created_at_desc created_at_asc name_asc].freeze
  before_action :fetch_kanban_board
  before_action :authorize_kanban_board_show
  before_action :fetch_kanban_stage
  before_action :authorize_kanban_board_update, only: :destroy_all

  def index
    @limit = cards_limit
    @result = KanbanCards::VisibleStageCardsQuery.new(
      account: Current.account,
      kanban_board: @kanban_board,
      kanban_stage: @kanban_stage,
      visible_cards: visible_cards_scope,
      limit: @limit,
      cursor: params[:cursor],
      terminal_period: sanitized_terminal_period
    ).call(load_cards: !metadata_only?)
  rescue KanbanCards::VisibleStageCardsQuery::RefreshRequiredError
    render json: { error: 'refresh_required' }, status: :conflict
  end

  def sort
    return render_invalid_sort if SORT_BY_VALUES.exclude?(params[:sort_by])

    KanbanCard.sort_active_cards_for_stage!(
      kanban_board: @kanban_board,
      kanban_stage: @kanban_stage,
      sort_by: params[:sort_by]
    )

    dispatch_kanban_card_reordered_event(@kanban_stage.id, @kanban_stage.id)
    head :no_content
  end

  def move_all
    target_board = target_kanban_board
    target_stage = target_board.kanban_stages.active.find_by(id: params[:target_stage_id])
    return render_terminal_stage_not_allowed if target_stage.blank? || terminal_stage?(target_stage, target_board)
    return move_all_cards_to_board(target_board, target_stage) if target_board != @kanban_board
    return head :no_content if target_stage == @kanban_stage

    KanbanCard.move_active_cards_to_stage!(
      kanban_board: @kanban_board,
      source_stage: @kanban_stage,
      target_stage: target_stage
    )

    dispatch_kanban_card_reordered_event(@kanban_stage.id, target_stage.id)
    head :no_content
  rescue KanbanCards::BulkActionRequest::Error => e
    render json: { error: e.code }, status: :unprocessable_content
  end

  def destroy_all
    KanbanCard.transaction do
      KanbanCard.lock_reorder_stages!([@kanban_stage.id])
      KanbanCard.lock_active_cards_for_stages!(@kanban_board, [@kanban_stage.id])
      @kanban_stage.kanban_cards.active.destroy_all
      KanbanCard.normalize_positions_for_stage!(kanban_board: @kanban_board, kanban_stage: @kanban_stage)
    end

    dispatch_kanban_card_deleted_event
    head :no_content
  end

  private

  def fetch_kanban_board
    @kanban_board = policy_scope(KanbanBoard).find(params[:kanban_board_id])
  end

  def authorize_kanban_board_show
    authorize @kanban_board, :show?
  end

  def authorize_kanban_board_update
    authorize @kanban_board, :update?
  end

  def fetch_kanban_stage
    @kanban_stage = @kanban_board.kanban_stages.active.find(params[:stage_id] || params[:id])
  end

  def target_kanban_board
    return @kanban_board if params[:target_kanban_board_id].blank?

    policy_scope(KanbanBoard).active.find(params[:target_kanban_board_id])
  end

  # Emptying a stage into another board is a bulk move of every card it holds, so it runs
  # through the same service the bulk bar uses and inherits its cap, per-card
  # authorization and events. Like the same-board move it answers with no content when
  # every card made it, and only spells out the cards when some of them did not.
  def move_all_cards_to_board(target_board, target_stage)
    card_ids = @kanban_stage.kanban_cards.active.order(:position, :id).pluck(:id)
    # An empty stage is nothing to move, not the missing-ids mistake the bulk bar makes.
    return head :no_content if card_ids.empty?

    result = KanbanCards::BulkActionService.new(
      user: Current.user,
      kanban_board: @kanban_board,
      target_kanban_board: target_board,
      operation: 'move',
      card_ids: card_ids,
      payload: { kanban_stage_id: target_stage.id }
    ).perform!
    return head :no_content if result.failed.empty?

    render json: { succeeded: result.succeeded, failed: result.failed }
  end

  # Collapsed columns still need fresh counters, so they refresh through the same
  # endpoint asking for totals only instead of skipping the request altogether.
  def metadata_only?
    ActiveModel::Type::Boolean.new.cast(params[:metadata_only]).present?
  end

  def cards_limit
    (params[:limit] || KanbanCards::VisibleStageCardsQuery::DEFAULT_LIMIT).to_i.clamp(
      1,
      KanbanCards::VisibleStageCardsQuery::MAX_LIMIT
    )
  end

  def terminal_stage?(stage, board)
    KanbanStage.special_stage_ids(board).include?(stage.id)
  end

  def render_invalid_sort
    render json: { error: 'invalid_sort' }, status: :unprocessable_content
  end

  def render_terminal_stage_not_allowed
    render json: { error: 'terminal_stage_not_allowed' }, status: :unprocessable_content
  end

  def dispatch_kanban_card_reordered_event(source_stage_id, target_stage_id)
    Rails.configuration.dispatcher.dispatch(
      Events::Types::KANBAN_CARD_REORDERED,
      Time.zone.now,
      account_id: @kanban_board.account_id,
      board_id: @kanban_board.id,
      source_stage_id: source_stage_id,
      target_stage_id: target_stage_id
    )
  end

  def dispatch_kanban_card_deleted_event
    Rails.configuration.dispatcher.dispatch(
      Events::Types::KANBAN_CARD_DELETED,
      Time.zone.now,
      account_id: @kanban_board.account_id,
      board_id: @kanban_board.id,
      stage_id: @kanban_stage.id
    )
  end
end
