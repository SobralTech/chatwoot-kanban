class Api::V1::Accounts::KanbanBoards::AutomationRulesController < Api::V1::Accounts::BaseController
  PREVIEW_LIMIT = 500

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

  def preview
    @preview_rule = KanbanAutomationRule.new(
      account: Current.account,
      kanban_board: @kanban_board,
      name: automation_rule_params[:name].presence || 'Preview',
      event_name: automation_rule_params[:event_name].presence || 'card_created',
      conditions: automation_rule_params[:conditions] || [],
      actions: automation_rule_params[:actions] || [],
      threshold_hours: automation_rule_params[:threshold_hours]
    )

    return render_preview_error unless @preview_rule.valid?

    cards = preview_cards
    matching_count = cards.first(PREVIEW_LIMIT).count do |card|
      KanbanAutomations::RuleMatcher.match?(card, @preview_rule)
    end

    render json: { count: matching_count, limit: PREVIEW_LIMIT, capped: cards.size > PREVIEW_LIMIT }
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
      :name, :description, :event_name, :position, :dry_run, :stop_after_match, :threshold_hours,
      conditions: [:attribute_key, :filter_operator, { values: [] }],
      actions: [:action_name, { action_params: {} }]
    )
  end

  def preview_cards
    @kanban_board.kanban_cards.active.order(:id).limit(PREVIEW_LIMIT + 1).to_a
  end

  def render_preview_error
    render json: { error: @preview_rule.errors.messages }, status: :unprocessable_content
  end

  def render_validation_error
    render json: { error: @automation_rule.errors.messages }, status: :unprocessable_content
  end
end
