class KanbanBoards::SummaryQuery
  Result = Struct.new(:open, :won_this_month, :lost_this_month, :average_ticket, :stages_summary, keyword_init: true)

  def initialize(account:, kanban_board:, visible_cards:)
    @account = account
    @kanban_board = kanban_board
    @visible_cards = visible_cards
  end

  def call
    metrics = KanbanCards::Totals.metrics(visible_cards, metric_conditions)

    Result.new(
      **metrics,
      average_ticket: average_ticket_for(metrics.fetch(:won_this_month)),
      stages_summary: stages_summary
    )
  end

  private

  attr_reader :account, :kanban_board, :visible_cards

  # `NOT IN ()` compiles to `1=1` and `IN ()` to `1=0`, so a board with no terminal
  # stages counts every card as open and reports won and lost at zero without a
  # branch here - and all three still come out of a single scan.
  def metric_conditions
    {
      open: card_table[:kanban_stage_id].not_in(KanbanStage.special_stage_ids(kanban_board)),
      won_this_month: entered_stage_this_month(kanban_board.won_stage_id),
      lost_this_month: entered_stage_this_month(kanban_board.lost_stage_id)
    }
  end

  def entered_stage_this_month(stage_id)
    card_table[:kanban_stage_id]
      .in(Array(stage_id))
      .and(card_table[:stage_entered_at].between(current_month_range))
  end

  def current_month_range
    now = Time.current.in_time_zone(account_time_zone)
    month_start = now.beginning_of_month
    month_start...month_start.next_month
  end

  def account_time_zone
    ActiveSupport::TimeZone[account.reporting_timezone.presence || Time.zone.name] || Time.zone
  end

  def average_ticket_for(metric)
    return if metric.count.zero?

    format('%.2f', metric.value / metric.count)
  end

  # Menu actions affect every active card in a stage, so their counts must not
  # inherit the visibility and view filters used by the funnel metrics.
  def stages_summary
    card_counts = kanban_board.kanban_cards.active.group(:kanban_stage_id).count

    kanban_board.kanban_stages.active.ordered.pluck(:id).map do |stage_id|
      { id: stage_id, cards_count: card_counts.fetch(stage_id, 0) }
    end
  end

  def card_table
    KanbanCard.arel_table
  end
end
