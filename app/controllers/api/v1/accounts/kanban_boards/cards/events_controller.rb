class Api::V1::Accounts::KanbanBoards::Cards::EventsController < Api::V1::Accounts::BaseController
  DEFAULT_LIMIT = 30
  MAX_LIMIT = 100

  before_action :fetch_kanban_board
  before_action :fetch_kanban_card

  def index
    authorize @kanban_card, :show?

    events = @kanban_card.kanban_card_events.includes(:user).order(created_at: :desc, id: :desc)
    events = events.where('kanban_card_events.id < ?', params[:before_id]) if params[:before_id].present?

    events = events.limit(limit + 1).to_a
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

  def limit
    (params[:limit] || DEFAULT_LIMIT).to_i.clamp(1, MAX_LIMIT)
  end
end
