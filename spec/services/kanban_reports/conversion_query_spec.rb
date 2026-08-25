require 'rails_helper'

RSpec.describe KanbanReports::ConversionQuery, type: :service do
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
    report_event(card: card, event_type: 'stage_changed', at: report_start + 1.day,
                 metadata: { from_stage_id: regular_stage.id, to_stage_id: won_stage.id })
  end

  it 'counts unique cards entering each stage during the period' do
    future_card = create(:kanban_card, account: account, kanban_board: board, kanban_stage: regular_stage, inbox: inbox)
    report_event(card: future_card, event_type: 'card_created', at: report_end + 1.day,
                 metadata: { stage_id: regular_stage.id })

    result = described_class.new(**report_query_options).call

    expect(result.map { |row| row.slice(:stage_name, :count) }).to eq(
      [
        { stage_name: 'Qualified', count: 1 },
        { stage_name: 'Won', count: 1 },
        { stage_name: 'Lost', count: 0 }
      ]
    )
  end
end
