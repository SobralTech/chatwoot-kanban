class KanbanReports::StageTimeQuery < KanbanReports::BaseQuery
  def call
    durations = durations_by_stage

    stages.map { |stage| stage_row(stage, durations) }
  end

  private

  def durations_by_stage
    rows = KanbanCardEvent.connection.select_rows(duration_aggregate_sql)
    rows.to_h do |stage_id, average_seconds, median_seconds, completed_count|
      [stage_id.to_i, { average: average_seconds.to_f.round(2), median: median_seconds.to_f.round(2), count: completed_count.to_i }]
    end
  end

  def stage_row(stage, durations)
    metrics = durations.fetch(stage.id, { average: 0.0, median: 0.0, count: 0 })
    {
      stage_id: stage.id,
      stage_name: stage.name,
      average_seconds: metrics.fetch(:average),
      median_seconds: metrics.fetch(:median),
      completed_count: metrics.fetch(:count)
    }
  end

  def duration_aggregate_sql
    <<~SQL.squish
      WITH normalized_events AS (#{normalized_events.to_sql}),
      stage_entries AS (
        SELECT stage_id, created_at,
               LEAD(created_at) OVER (PARTITION BY kanban_card_id ORDER BY created_at, id) AS exited_at
        FROM normalized_events
        WHERE stage_id IS NOT NULL
      ),
      durations AS (
        SELECT stage_id, EXTRACT(EPOCH FROM exited_at - created_at) AS seconds
        FROM stage_entries
        WHERE exited_at > created_at
      )
      SELECT stage_id, AVG(seconds),
             PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY seconds),
             COUNT(*)
      FROM durations
      GROUP BY stage_id
    SQL
  end

  def normalized_events
    events_until_cutoff
      .reorder(nil)
      .select(:kanban_card_id, :created_at, :id, Arel.sql("#{stage_id_sql} AS stage_id"))
  end
end
