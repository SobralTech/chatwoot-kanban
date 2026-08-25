module KanbanReportsHelpers
  def report_query_options(overrides = {})
    {
      account: account,
      kanban_board: board,
      user: administrator,
      since: report_start,
      until: report_end,
      group_by: 'day',
      timezone_offset: 0,
      agent_ids: [],
      inbox_ids: [],
      labels: []
    }.merge(overrides)
  end

  def report_event(card:, event_type:, at:, metadata: {})
    create(
      :kanban_card_event,
      account: account,
      kanban_card: card,
      kanban_board: board,
      event_type: event_type,
      metadata: metadata,
      created_at: at
    )
  end

  def build_report_board
    report_board = create(:kanban_board, account: account)
    regular_stage = create(:kanban_stage, account: account, kanban_board: report_board, position: 1, name: 'Qualified')
    won_stage = create(:kanban_stage, account: account, kanban_board: report_board, position: 2, name: 'Won')
    lost_stage = create(:kanban_stage, account: account, kanban_board: report_board, position: 3, name: 'Lost')
    report_board.update!(won_stage_id: won_stage.id, lost_stage_id: lost_stage.id)
    [report_board, regular_stage, won_stage, lost_stage]
  end
end

RSpec.configure do |config|
  config.include KanbanReportsHelpers, type: :service
end
