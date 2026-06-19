class Api::V1::Accounts::KanbanBoards::Cards::AssigneesController < Api::V1::Accounts::BaseController
  before_action :fetch_kanban_board
  before_action :fetch_kanban_card

  def index
    authorize @kanban_card, :show?
    fetch_assignees
    fetch_assignable_users
  end

  def update
    authorize @kanban_card, :update?
    return render_unknown_assignees if unknown_assignee_ids.present?

    @kanban_card.update_assignees!(assignee_ids)
    fetch_assignees
    fetch_assignable_users
    render :index
  end

  private

  def fetch_kanban_board
    @kanban_board = policy_scope(KanbanBoard).find(params[:kanban_board_id])
  end

  def fetch_kanban_card
    @kanban_card = @kanban_board.kanban_cards.active.joins(:kanban_stage).merge(KanbanStage.active).find(params[:id])
  end

  def fetch_assignees
    @assignees = @kanban_card.assignees
  end

  def fetch_assignable_users
    @assignable_users = @kanban_board.assignable_users.order(:name)
  end

  def assignee_ids
    @assignee_ids ||= Array(params[:assignee_ids]).filter_map(&:presence).map(&:to_i).uniq
  end

  def assignable_user_ids
    @assignable_user_ids ||= @kanban_board.assignable_users.where(id: assignee_ids).pluck(:id)
  end

  def unknown_assignee_ids
    @unknown_assignee_ids ||= assignee_ids - assignable_user_ids
  end

  def render_unknown_assignees
    render json: { error: "Unknown assignees: #{unknown_assignee_ids.join(', ')}" }, status: :unprocessable_entity
  end
end
