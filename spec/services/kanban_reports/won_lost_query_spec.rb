require 'rails_helper'

RSpec.describe KanbanReports::WonLostQuery, type: :service do
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
    report_event(card: card, event_type: 'won', at: report_start + 2.days, metadata: { stage_id: won_stage.id })
    report_event(card: card, event_type: 'reopened', at: report_start + 3.days,
                 metadata: { from_stage_id: won_stage.id, to_stage_id: regular_stage.id })
    report_event(card: card, event_type: 'won', at: report_start + 4.days, metadata: { stage_id: won_stage.id })
  end

  it 'deduplicates repeated wins in the chart and total' do
    result = described_class.new(**report_query_options).call

    expect(result[:totals]).to eq(won: 1, lost: 0)
    expect(result[:series].sum { |row| row[:won] }).to eq(1)
    expect(result[:series].length).to eq(8)
    expect(result[:series].last[:period]).to eq('2026-08-08')
  end
end
