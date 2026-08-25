require 'rails_helper'

RSpec.describe KanbanReports::SummaryQuery, type: :service do
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
    card.update!(stage_entered_at: report_start + 3.days)
    report_event(card: card, event_type: 'won', at: report_start + 3.days, metadata: { stage_id: won_stage.id })
    report_event(card: card, event_type: 'reopened', at: report_start + 4.days,
                 metadata: { from_stage_id: won_stage.id, to_stage_id: regular_stage.id })
    report_event(card: card, event_type: 'won', at: report_start + 5.days, metadata: { stage_id: won_stage.id })
  end

  it 'counts a card only once after it is reopened and won again' do
    result = described_class.new(**report_query_options).call

    expect(result[:open][:count]).to eq(0)
    expect(result[:won][:count]).to eq(1)
    expect(result[:lost][:count]).to eq(0)
    expect(result[:conversion_rate]).to eq(100.0)
  end
end
