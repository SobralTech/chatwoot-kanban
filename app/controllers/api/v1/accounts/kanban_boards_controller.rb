class Api::V1::Accounts::KanbanBoardsController < Api::V1::Accounts::BaseController
  include KanbanCardFilterParams
  before_action :check_authorization
  before_action :fetch_kanban_board, only: [:show, :update, :destroy]

  def index
    @kanban_boards = policy_scope(KanbanBoard).ordered.to_a
    fetch_overview_data
  end

  def templates
    @templates = KanbanBoards::TemplateCatalog.previews(locale: Current.account.locale)
  end

  def show
    sanitized_inbox_filter_ids
    sanitized_assignee_filter_ids
    sanitized_card_statuses
    sanitized_priorities
    sanitized_due_dates
    sanitized_created_dates
    sanitized_labels
    sanitized_match_mode
    sanitized_terminal_period
    @kanban_stages = @kanban_board.kanban_stages.active.ordered
    fetch_stage_card_results
  end

  # A board cannot be born active: activation requires the won, lost and regular stages
  # that ApplyTemplateService only creates afterwards. The transaction keeps a rejected
  # activation (a duplicate name, say) from leaving a stageless board behind.
  def create
    KanbanBoard.transaction do
      @kanban_board = KanbanBoard.create!(kanban_board_params.merge(account: Current.account, active: false))
      KanbanBoards::ApplyTemplateService.new(kanban_board: @kanban_board, template_key: params[:template_key]).perform!
      @kanban_board.update!(active: true)
    end
  end

  def update
    @kanban_board.update!(kanban_board_params)
    dispatch_kanban_board_event(Events::Types::KANBAN_BOARD_UPDATED)
  end

  def destroy
    @kanban_board.update!(active: false)
    head :no_content
  end

  private

  def fetch_kanban_board
    # Deleting a board only deactivates it, and an administrator has to be able to reopen
    # a deactivated board to switch it back on. policy_scope resolves from scope.active,
    # so admins bypass it here; non-admins keep the active + visibility restriction.
    @kanban_board = if Current.account_user&.administrator?
                      KanbanBoard.where(account_id: Current.account.id).find(params[:id])
                    else
                      policy_scope(KanbanBoard).find(params[:id])
                    end
  end

  def fetch_overview_data
    board_ids = @kanban_boards.map(&:id)

    @overview_stages_by_board_id = {}
    @overview_cards_count_by_board_id = {}
    @overview_cards_count_by_stage_id = {}
    @overview_visible_users_by_board_id = {}
    @overview_allowed_inboxes_by_board_id = {}
    @overview_entry_rule_scope_by_board_id = {}

    return if board_ids.blank?

    overview_stages = active_overview_stages(board_ids)
    stage_ids = overview_stages.map(&:id)

    @overview_stages_by_board_id = overview_stages.group_by(&:kanban_board_id)
    @overview_cards_count_by_board_id = active_kanban_card_counts(:kanban_board_id, kanban_board_id: board_ids)
    @overview_cards_count_by_stage_id = active_kanban_card_counts(:kanban_stage_id, kanban_stage_id: stage_ids)
    @overview_visible_users_by_board_id = overview_visible_users_by_board_id(board_ids)
    @overview_allowed_inboxes_by_board_id = overview_allowed_inboxes_by_board_id(board_ids)
    @overview_entry_rule_scope_by_board_id = overview_entry_rule_scope_by_board_id(board_ids)
  end

  def active_overview_stages(board_ids)
    KanbanStage.where(account_id: Current.account.id, kanban_board_id: board_ids)
               .active.ordered.to_a
  end

  def active_kanban_card_counts(group_key, filters)
    KanbanCard.active
              .where(account_id: Current.account.id)
              .where(filters)
              .group(group_key).count
  end

  def overview_visible_users_by_board_id(board_ids)
    KanbanBoardMember.includes(user: { avatar_attachment: :blob })
                     .where(account_id: Current.account.id, kanban_board_id: board_ids)
                     .order(:user_id)
                     .group_by(&:kanban_board_id)
                     .transform_values { |members| members.map(&:user) }
  end

  # The overview badge lists the inboxes a board takes in, which is the union of what its
  # active entry rules name. A board whose rules cover every inbox contributes nothing
  # here: the view reads `inbox_scope_mode` for that case.
  def overview_allowed_inboxes_by_board_id(board_ids)
    KanbanBoardEntryRuleInbox.includes(:inbox)
                             .where(account_id: Current.account.id, kanban_board_id: board_ids)
                             .where(kanban_board_entry_rule_id: KanbanBoardEntryRule.active.select(:id))
                             .order(:inbox_id)
                             .group_by(&:kanban_board_id)
                             .transform_values { |rule_inboxes| rule_inboxes.map(&:inbox).uniq }
  end

  def overview_entry_rule_scope_by_board_id(board_ids)
    KanbanBoardEntryRule.active
                        .where(account_id: Current.account.id, kanban_board_id: board_ids)
                        .group(:kanban_board_id)
                        .pluck(
                          :kanban_board_id,
                          Arel.sql('BOOL_OR(all_inboxes)'),
                          Arel.sql('ARRAY_AGG(name ORDER BY position, id) FILTER (WHERE all_inboxes)')
                        )
                        .to_h do |board_id, all_inboxes, all_inbox_rule_names|
      [board_id, { all_inboxes: all_inboxes, all_inbox_rule_names: all_inbox_rule_names || [] }]
    end
  end

  def kanban_board_params
    params.require(:kanban_board).permit(
      :name, :description, :position, :active,
      :won_stage_id, :lost_stage_id, :lost_reason_required,
      automation_settings: {}
    )
  end

  def fetch_stage_card_results
    @stage_card_limit = KanbanCards::VisibleStageCardsQuery::DEFAULT_LIMIT
    visible_cards = visible_cards_scope
    @stage_card_results = @kanban_stages.index_with do |kanban_stage|
      query = KanbanCards::VisibleStageCardsQuery.new(
        account: Current.account,
        kanban_board: @kanban_board,
        kanban_stage: kanban_stage,
        visible_cards: visible_cards,
        limit: @stage_card_limit,
        terminal_period: sanitized_terminal_period,
        filtered_stage_sla: sanitized_filter_values(:stage_sla, KanbanCards::VisibleStageCardsQuery::STAGE_SLA_VALUES)
      )
      query.call(load_cards: sanitized_collapsed_stage_ids.exclude?(kanban_stage.id))
    end
  end

  def dispatch_kanban_board_event(event_name)
    Rails.configuration.dispatcher.dispatch(event_name, Time.zone.now, account_id: @kanban_board.account_id, board_id: @kanban_board.id)
  end
end
