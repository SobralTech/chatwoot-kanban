class KanbanReports::ConversionQuery < KanbanReports::BaseQuery
  def call
    counts_by_stage = stage_entry_counts

    stages.map.with_index { |stage, index| stage_row(stage, index, counts_by_stage) }
  end

  private

  def stage_entry_counts
    period_events(types: STAGE_EVENT_TYPES)
      .reorder(nil)
      .where("#{stage_id_sql} IS NOT NULL")
      .group(Arel.sql(stage_id_sql))
      .distinct
      .count(:kanban_card_id)
      .transform_keys(&:to_i)
  end

  def stage_row(stage, index, counts_by_stage)
    count = counts_by_stage.fetch(stage.id, 0)
    previous_count = index.zero? ? count : counts_by_stage.fetch(stages[index - 1].id, 0)

    {
      stage_id: stage.id,
      stage_name: stage.name,
      position: stage.position,
      count: count,
      conversion_rate: index.zero? ? 100.0 : percentage(count, previous_count)
    }
  end
end
