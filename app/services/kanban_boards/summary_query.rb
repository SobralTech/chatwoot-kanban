class KanbanBoards::SummaryQuery
  Metric = Data.define(:count, :value)
  Result = Struct.new(:open, :won_this_month, :lost_this_month, :average_ticket, :currency, keyword_init: true)

  CURRENCY = 'BRL'.freeze

  # rubocop:disable Metrics/ParameterLists
  def initialize(account:, user:, kanban_board:, visible_inbox_ids: nil, visible_team_ids: nil, account_user: nil,
                 filtered_inbox_ids: nil, filtered_assignee_ids: nil, filtered_card_statuses: nil,
                 filtered_priorities: nil, filtered_due_dates: nil, filtered_labels: nil, match_mode: nil,
                 search_query: nil)
    @account = account
    @kanban_board = kanban_board
    @visible_cards_scope = KanbanCards::VisibleCardsScope.new(
      account: account,
      user: user,
      kanban_board: kanban_board,
      visible_inbox_ids: visible_inbox_ids,
      visible_team_ids: visible_team_ids,
      account_user: account_user,
      filtered_inbox_ids: filtered_inbox_ids,
      filtered_assignee_ids: filtered_assignee_ids,
      filtered_card_statuses: filtered_card_statuses,
      filtered_priorities: filtered_priorities,
      filtered_due_dates: filtered_due_dates,
      filtered_labels: filtered_labels,
      match_mode: match_mode,
      search_query: search_query
    )
  end
  # rubocop:enable Metrics/ParameterLists

  def call
    return empty_result unless valid_board?

    open_metric = aggregate(open_cards_scope)
    won_metric = aggregate(cards_for_stage_this_month(kanban_board.won_stage_id))
    lost_metric = aggregate(cards_for_stage_this_month(kanban_board.lost_stage_id))

    Result.new(
      open: open_metric,
      won_this_month: won_metric,
      lost_this_month: lost_metric,
      average_ticket: average_ticket_for(won_metric),
      currency: CURRENCY
    )
  end

  private

  attr_reader :account, :kanban_board

  def empty_result
    zero = Metric.new(0, '0.0')
    Result.new(open: zero, won_this_month: zero, lost_this_month: zero, average_ticket: nil, currency: CURRENCY)
  end

  def valid_board?
    kanban_board.account_id == account.id && kanban_board.active?
  end

  def visible_cards
    @visible_cards ||= @visible_cards_scope.call
  end

  def open_cards_scope
    special_stage_ids = KanbanStage.special_stage_ids(kanban_board)
    return visible_cards if special_stage_ids.blank?

    visible_cards.where.not(kanban_stage_id: special_stage_ids)
  end

  def cards_for_stage_this_month(stage_id)
    return visible_cards.where(kanban_stage_id: nil) if stage_id.blank?

    visible_cards
      .where(kanban_stage_id: stage_id)
      .where(stage_entered_at: current_month_range)
  end

  def current_month_range
    now = Time.current.in_time_zone(account_time_zone)
    month_start = now.beginning_of_month
    month_start...month_start.next_month
  end

  def account_time_zone
    ActiveSupport::TimeZone[account.reporting_timezone.presence || Time.zone.name] || Time.zone
  end

  def aggregate(scope)
    count, value = scope
                   .left_outer_joins(:kanban_card_products)
                   .pick(KanbanCard.arel_table[:id].count(true), total_value_expression)

    Metric.new(count.to_i, decimal_string(value))
  end

  def average_ticket_for(metric)
    return if metric.count.zero?

    format('%.2f', BigDecimal(metric.value) / metric.count)
  end

  def decimal_string(value)
    BigDecimal(value.to_s).to_s('F')
  end

  def total_value_expression
    Arel::Nodes::NamedFunction.new(
      'COALESCE',
      [
        Arel::Nodes::NamedFunction.new(
          'SUM',
          [KanbanCardProduct.arel_table[:unit_price] * KanbanCardProduct.arel_table[:quantity]]
        ),
        Arel::Nodes.build_quoted(0)
      ]
    )
  end
end
