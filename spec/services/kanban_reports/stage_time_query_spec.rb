require 'rails_helper'

RSpec.describe KanbanReports::StageTimeQuery, type: :service do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:board_data) { build_report_board }
  let(:board) { board_data.first }
  let(:regular_stage) { board_data.second }
  let(:won_stage) { board_data.third }
  let(:lost_stage) { board_data.fourth }
  let(:report_start) { Time.zone.parse('2026-08-01 00:00:00 UTC') }
  let(:report_end) { Time.zone.parse('2026-08-08 00:00:00 UTC') }
  let(:card) { create(:kanban_card, account: account, kanban_board: board, kanban_stage: won_stage, inbox: inbox) }

  before do
    report_event(card: card, event_type: 'card_created', at: report_start, metadata: { stage_id: regular_stage.id })
    report_event(card: card, event_type: 'stage_changed', at: report_start + 2.hours,
                 metadata: { from_stage_id: regular_stage.id, to_stage_id: won_stage.id })
  end

  it 'returns completed durations and excludes the current stage without an exit' do
    result = described_class.new(**report_query_options).call

    regular = result.find { |row| row[:stage_id] == regular_stage.id }
    won = result.find { |row| row[:stage_id] == won_stage.id }

    expect(regular[:average_seconds]).to eq(7200.0)
    expect(regular[:median_seconds]).to eq(7200.0)
    expect(regular[:completed_count]).to eq(1)
    expect(won[:completed_count]).to eq(0)
  end
end
