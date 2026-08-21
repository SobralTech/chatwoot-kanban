class Api::V1::Accounts::KanbanBoards::AutomationLogsController < Api::V1::Accounts::BaseController
  include KanbanAutomationAuthorization

  DEFAULT_LIMIT = 50
  MAX_LIMIT = 100

  before_action :fetch_kanban_board
  before_action :authorize_kanban_board

  def index
    @automation_logs = filtered_logs.limit(limit)
  end

  private

  def fetch_kanban_board
    @kanban_board = KanbanBoard.where(account_id: Current.account.id).find(params[:kanban_board_id])
  end

  def authorize_kanban_board
    with_automation_authorization { authorize @kanban_board, :update? }
  end

  def filtered_logs
    apply_filters(base_logs)
  end

  def base_logs
    @kanban_board.kanban_automation_logs
                 .includes(:kanban_automation_rule)
                 .order(created_at: :desc, id: :desc)
  end

  def apply_filters(scope)
    scope = scope.where(kanban_automation_rule_id: params[:rule_id]) if params[:rule_id].present?
    scope = scope.where(kanban_card_id: params[:card_id]) if params[:card_id].present?
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = apply_period_filter(scope, :from, '>')
    apply_period_filter(scope, :to, '<=')
  end

  def apply_period_filter(scope, key, operator)
    value = parsed_time(params[key])
    return scope unless value

    scope.where("created_at #{operator} ?", value)
  end

  def parsed_time(value)
    return if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def limit
    (params[:limit] || DEFAULT_LIMIT).to_i.clamp(1, MAX_LIMIT)
  end
end
