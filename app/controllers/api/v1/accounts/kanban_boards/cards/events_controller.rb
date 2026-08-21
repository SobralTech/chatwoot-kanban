class Api::V1::Accounts::KanbanBoards::Cards::EventsController < Api::V1::Accounts::KanbanBoards::Cards::BaseController
  def index
    authorize @kanban_card, :show?

    @events, @has_more, @next_cursor = cursor_page(@kanban_card.kanban_card_events.includes(:user).recent_first)
    @automation_rule_names = automation_rule_names
  end

  private

  # Resolved here in one query so the timeline does not have to fetch the board's rules
  # to put a name on an automation entry.
  def automation_rule_names
    rule_ids = @events.filter_map { |event| event.metadata['automation_rule_id'] }.uniq
    return {} if rule_ids.empty?

    KanbanAutomationRule.where(id: rule_ids, kanban_board_id: @kanban_card.kanban_board_id).pluck(:id, :name).to_h
  end
end
