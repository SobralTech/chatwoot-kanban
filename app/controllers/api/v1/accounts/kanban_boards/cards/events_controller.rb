class Api::V1::Accounts::KanbanBoards::Cards::EventsController < Api::V1::Accounts::KanbanBoards::Cards::BaseController
  def index
    authorize @kanban_card, :show?

    @events, @has_more, @next_cursor = cursor_page(@kanban_card.kanban_card_events.includes(:user).recent_first)
  end
end
