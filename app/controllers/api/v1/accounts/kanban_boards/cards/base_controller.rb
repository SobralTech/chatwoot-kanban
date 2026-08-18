# Every controller in this namespace addresses a sub-resource of one card, so they all
# resolve the same board -> card pair before doing anything else.
class Api::V1::Accounts::KanbanBoards::Cards::BaseController < Api::V1::Accounts::BaseController
  DEFAULT_LIMIT = 30
  MAX_LIMIT = 100

  before_action :fetch_kanban_board
  before_action :fetch_kanban_card

  private

  def fetch_kanban_board
    @kanban_board = policy_scope(KanbanBoard).find(params[:kanban_board_id])
  end

  def fetch_kanban_card
    @kanban_card = @kanban_board.kanban_cards.active.joins(:kanban_stage).merge(KanbanStage.active).find(params[:id])
  end

  # Returns one page of a card's timeline collection plus the cursor for the next one.
  def cursor_page(scope)
    records = cursor_scope(scope).limit(page_limit + 1).to_a
    has_more = records.length > page_limit
    records = records.first(page_limit)

    [records, has_more, has_more ? records.last.id : nil]
  end

  # The cursor compares the whole sort key, not just the id: backfilled rows carry a
  # fresh id with an old created_at, so an id-only cursor would skip them.
  def cursor_scope(scope)
    return scope if params[:before_id].blank?

    cursor = scope.find(params[:before_id])
    table = scope.table_name
    scope.where("(#{table}.created_at, #{table}.id) < (?, ?)", cursor.created_at, cursor.id)
  end

  def page_limit
    @page_limit ||= (params[:limit] || DEFAULT_LIMIT).to_i.clamp(1, MAX_LIMIT)
  end
end
