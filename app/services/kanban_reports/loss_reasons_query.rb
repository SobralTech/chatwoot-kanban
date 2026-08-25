class KanbanReports::LossReasonsQuery < KanbanReports::BaseQuery
  def call
    lost_events = unique_lost_events
    grouped_events = group_by_reason(lost_events)
    rows = grouped_events.map { |(reason_id, title), events| reason_row(reason_id, title, events, lost_events.length) }

    rows.sort_by { |row| [-row[:count], row[:reason_title].to_s] }
  end

  private

  def unique_lost_events
    unique_terminal_events.select { |event| event.event_type == 'lost' }
  end

  def group_by_reason(events)
    reason_titles = kanban_board.kanban_reasons.pluck(:id, :title).to_h
    events.group_by { |event| reason_key(event, reason_titles) }
  end

  def reason_key(event, reason_titles)
    reason_id = event.metadata&.dig('reason_id')&.to_i
    title = event.metadata&.dig('reason_title').presence || reason_titles[reason_id] || 'No reason'
    [reason_id.presence, title]
  end

  def reason_row(reason_id, title, events, total)
    {
      reason_id: reason_id,
      reason_title: title,
      count: events.length,
      percentage: percentage(events.length, total)
    }
  end
end
