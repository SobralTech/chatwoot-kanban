class KanbanReports::StageTimeQuery < KanbanReports::BaseQuery
  def call
    durations = durations_by_stage

    stages.map { |stage| stage_row(stage, durations) }
  end

  private

  def durations_by_stage
    events_by_card = events_until_cutoff.group_by(&:kanban_card_id)
    filtered_cards.select(:id).find_each.with_object(Hash.new { |hash, stage_id| hash[stage_id] = [] }) do |card, durations|
      collect_card_durations(events_by_card.fetch(card.id, []), durations)
    end
  end

  def collect_card_durations(events, durations)
    current_stage_id = nil
    entered_at = nil

    events.each do |event|
      next_stage_id = stage_entry(event)
      next if next_stage_id.blank?

      add_duration(durations, current_stage_id, entered_at, event.created_at)
      current_stage_id = next_stage_id
      entered_at = event.created_at
    end
    # The current interval intentionally is not added: it has no exit event yet.
  end

  def add_duration(durations, stage_id, entered_at, exited_at)
    return unless stage_id.present? && entered_at.present? && (exited_at > entered_at)

    durations[stage_id] << (exited_at - entered_at)
  end

  def stage_row(stage, durations)
    values = durations[stage.id].sort
    {
      stage_id: stage.id,
      stage_name: stage.name,
      average_seconds: average(values),
      median_seconds: median(values),
      completed_count: values.length
    }
  end

  def average(values)
    return 0.0 if values.empty?

    (values.sum / values.length).round(2)
  end

  def median(values)
    return 0.0 if values.empty?

    middle = values.length / 2
    return values[middle].round(2) if values.length.odd?

    ((values[middle - 1] + values[middle]) / 2).round(2)
  end
end
