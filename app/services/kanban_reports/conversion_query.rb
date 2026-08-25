class KanbanReports::ConversionQuery < KanbanReports::BaseQuery
  def call
    cards_by_stage = Hash.new { |hash, stage_id| hash[stage_id] = {} }

    period_events(types: STAGE_EVENT_TYPES).each do |event|
      stage_id = stage_entry(event)
      next if stage_id.blank?

      cards_by_stage[stage_id][event.kanban_card_id] = true
    end

    stages.map.with_index { |stage, index| stage_row(stage, index, cards_by_stage) }
  end

  private

  def stage_row(stage, index, cards_by_stage)
    count = cards_by_stage[stage.id].length
    previous_count = index.zero? ? count : cards_by_stage[stages[index - 1].id].length

    {
      stage_id: stage.id,
      stage_name: stage.name,
      position: stage.position,
      count: count,
      conversion_rate: index.zero? ? 100.0 : percentage(count, previous_count)
    }
  end
end
