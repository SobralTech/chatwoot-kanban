class KanbanReports::SummaryQuery < KanbanReports::BaseQuery
  def call
    won_events = unique_terminal_events.select { |event| event.event_type == 'won' }
    lost_events = unique_terminal_events.select { |event| event.event_type == 'lost' }
    won_metric = metric_for(card_ids_for_events(won_events))

    {
      open: metric_payload(open_metric),
      won: metric_payload(won_metric),
      lost: metric_payload(metric_for(card_ids_for_events(lost_events))),
      average_ticket: average_ticket(won_metric),
      conversion_rate: percentage(won_events.length, won_events.length + lost_events.length)
    }
  end

  private

  def open_metric
    special_stage_ids = KanbanStage.special_stage_ids(kanban_board)
    metric_for_scope(filtered_cards.where.not(kanban_stage_id: special_stage_ids))
  end

  def average_ticket(metric)
    return '0.00' if metric.count.zero?

    format('%.2f', metric.value / metric.count)
  end
end
