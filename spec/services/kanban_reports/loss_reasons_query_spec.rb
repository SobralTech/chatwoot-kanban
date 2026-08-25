require 'rails_helper'

RSpec.describe KanbanReports::LossReasonsQuery, type: :service do
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
  let(:reason) { KanbanReason.create!(account: account, kanban_board: board, reason_type: :lost, title: 'Budget') }
  let(:card) { create(:kanban_card, account: account, kanban_board: board, kanban_stage: lost_stage, inbox: inbox) }

  before do
    report_event(card: card, event_type: 'lost', at: report_start + 1.day,
                 metadata: { stage_id: lost_stage.id, reason_id: reason.id, reason_title: reason.title })
  end

  it 'ranks reasons from lost event metadata' do
    result = described_class.new(**report_query_options).call

    expect(result).to include(
      hash_including(reason_id: reason.id, reason_title: 'Budget', count: 1, percentage: 100.0)
    )
  end
end
