class Api::V1::Accounts::KanbanBoards::AutomationRulesController < Api::V1::Accounts::BaseController
  before_action :fetch_kanban_board
  before_action :fetch_automation_rule, only: [:update, :destroy, :toggle]
  before_action :check_authorization

  def index
    @automation_rules = policy_scope(KanbanAutomationRule)
                        .where(kanban_board_id: @kanban_board.id)
                        .ordered
  end

  def create
    @automation_rule = KanbanAutomationRule.new(
      automation_rule_params.merge(
        account: Current.account,
        kanban_board: @kanban_board,
        created_by: Current.user,
        active: false,
        dry_run: true
      )
    )

    return render_validation_error unless @automation_rule.save
  end

  def update
    @automation_rule.assign_attributes(automation_rule_params)
    return render_validation_error unless @automation_rule.save
  end

  def destroy
    @automation_rule.destroy!
    head :no_content
  end

  def toggle
    @automation_rule.update!(active: !@automation_rule.active?)
  end

  private

  def fetch_kanban_board
    @kanban_board = KanbanBoard.where(account_id: Current.account.id).find(params[:kanban_board_id])
  end

  def fetch_automation_rule
    @automation_rule = KanbanAutomationRule.where(
      account_id: Current.account.id,
      kanban_board_id: @kanban_board.id
    ).find(params[:id])
  end

  def check_authorization
    authorize(@automation_rule || KanbanAutomationRule)
  rescue Pundit::NotAuthorizedError
    render json: { error: 'You are not authorized to do this action' }, status: :forbidden
  end

  def automation_rule_params
    params.require(:automation_rule).permit(
      :name, :description, :event_name, :position, :dry_run, :stop_after_match,
      conditions: [:attribute_key, :filter_operator, { values: [] }],
      actions: [:action_name, { action_params: {} }]
    )
  end

  def render_validation_error
    render json: { error: @automation_rule.errors.messages }, status: :unprocessable_content
  end
end
