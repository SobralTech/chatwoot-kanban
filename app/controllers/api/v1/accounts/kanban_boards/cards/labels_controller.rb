class Api::V1::Accounts::KanbanBoards::Cards::LabelsController < Api::V1::Accounts::KanbanBoards::Cards::BaseController
  def index
    authorize @kanban_card, :show?
    fetch_labels
  end

  def update
    authorize @kanban_card, :update?
    return render_unknown_labels if unknown_label_titles.present?

    previous_label_titles = @kanban_card.label_list.to_a
    KanbanCard.transaction do
      @kanban_card.update_labels(label_titles)
      KanbanCards::RecordEventService.labels_changed(
        card: @kanban_card, from: previous_label_titles, to: label_titles, user: Current.user
      )
    end
    fetch_labels
    render :index
  end

  private

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
