class KanbanBoards::SummaryQuery
  Metric = Data.define(:count, :value)
  Result = Struct.new(:open, :won_this_month, :lost_this_month, :average_ticket, keyword_init: true)

  ZERO_METRIC = Metric.new(0, '0.0')

  def initialize(account:, kanban_board:, visible_cards:)
    @account = account
    @kanban_board = kanban_board
    @visible_cards = visible_cards
  end

  def call
    won_metric = metric_for_stage_this_month(kanban_board.won_stage_id)

    Result.new(
      open: aggregate(open_cards_scope),
      won_this_month: won_metric,
      lost_this_month: metric_for_stage_this_month(kanban_board.lost_stage_id),
      average_ticket: average_ticket_for(won_metric)
    )
  end

  private

  attr_reader :account, :kanban_board, :visible_cards

  # An empty special-stage list compiles to `1=1`, so every card counts as open.
  def open_cards_scope
    visible_cards.where.not(kanban_stage_id: KanbanStage.special_stage_ids(kanban_board))
  end

  # A board without a won/lost stage has nothing to count, so it never reaches the database.
  def metric_for_stage_this_month(stage_id)
    return ZERO_METRIC if stage_id.blank?

    aggregate(visible_cards.where(kanban_stage_id: stage_id, stage_entered_at: current_month_range))
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
