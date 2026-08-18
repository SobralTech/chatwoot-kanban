class Api::V1::Accounts::KanbanBoards::Cards::EventsController < Api::V1::Accounts::BaseController
  DEFAULT_LIMIT = 30
  MAX_LIMIT = 100

  before_action :fetch_kanban_board
  before_action :fetch_kanban_card

  def index
    authorize @kanban_card, :show?

    events = paginated_events.limit(limit + 1).to_a
    @has_more = events.length > limit
    @events = events.first(limit)
    @next_cursor = @has_more ? @events.last.id : nil
  end

  private

  def fetch_kanban_board
    @kanban_board = policy_scope(KanbanBoard).find(params[:kanban_board_id])
  end

  def fetch_kanban_card
    @kanban_card = @kanban_board.kanban_cards.active.joins(:kanban_stage).merge(KanbanStage.active).find(params[:id])
  end

  # The cursor compares the whole sort key, not just the id: backfilled events carry
  # a fresh id with an old created_at, so an id-only cursor would skip them.
  def paginated_events
    events = @kanban_card.kanban_card_events.includes(:user).recent_first
    return events if params[:before_id].blank?

    cursor = @kanban_card.kanban_card_events.find(params[:before_id])
    events.where('(kanban_card_events.created_at, kanban_card_events.id) < (?, ?)', cursor.created_at, cursor.id)
  end

  def limit
    (params[:limit] || DEFAULT_LIMIT).to_i.clamp(1, MAX_LIMIT)
  end
end
