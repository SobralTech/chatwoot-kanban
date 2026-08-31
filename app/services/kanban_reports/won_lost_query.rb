class KanbanReports::WonLostQuery < KanbanReports::BaseQuery
  def call
    terminal_events = unique_terminal_events
    series_events = terminal_events.group_by { |event| period_bucket(event.created_at) }

    {
      totals: {
        won: terminal_events.count { |event| event.event_type == 'won' },
        lost: terminal_events.count { |event| event.event_type == 'lost' }
      },
      series: series(series_events)
    }
  end

  private

  def series(events_by_bucket)
    first_bucket = period_bucket(since)
    last_bucket = period_bucket(self.until)
    rows = []
    bucket = first_bucket

    while bucket <= last_bucket
      events = events_by_bucket.fetch(bucket, [])
      rows << {
        period: bucket_label(bucket),
        timestamp: bucket.to_i,
        won: events.count { |event| event.event_type == 'won' },
        lost: events.count { |event| event.event_type == 'lost' }
      }
      bucket = next_bucket(bucket)
    end

    rows
  end

  def next_bucket(bucket)
    return bucket.next_month if group_by == 'month'
    return bucket + 1.week if group_by == 'week'

    bucket + 1.day
  end
end
