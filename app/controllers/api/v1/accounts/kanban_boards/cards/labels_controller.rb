class Api::V1::Accounts::KanbanBoards::Cards::LabelsController < Api::V1::Accounts::BaseController
  before_action :fetch_kanban_board
  before_action :fetch_kanban_card

  def index
    authorize @kanban_card, :show?
    fetch_labels
  end

  def update
    authorize @kanban_card, :update?
    return render_unknown_labels if unknown_label_titles.present?

    @kanban_card.update_labels(label_titles)
    fetch_labels
    render :index
  end

  private

  def fetch_kanban_board
    @kanban_board = policy_scope(KanbanBoard).find(params[:kanban_board_id])
  end

  def fetch_kanban_card
    @kanban_card = @kanban_board.kanban_cards.active.joins(:kanban_stage).merge(KanbanStage.active).find(params[:id])
  end

  def fetch_labels
    @labels = Current.account.labels.where(title: @kanban_card.label_list)
  end

  def label_titles
    @label_titles ||= Array(params[:labels]).uniq
  end

  def account_label_titles
    @account_label_titles ||= Current.account.labels.where(title: label_titles).pluck(:title)
  end

  def unknown_label_titles
    @unknown_label_titles ||= label_titles - account_label_titles
  end

  def render_unknown_labels
    render json: { error: "Unknown labels: #{unknown_label_titles.join(', ')}" }, status: :unprocessable_entity
  end
end
