require 'rails_helper'

RSpec.describe KanbanReports::AgentsQuery, type: :service do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
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
    KanbanCardAssignee.create!(account: account, kanban_card: card, user: agent)
    report_event(card: card, event_type: 'won', at: report_start + 1.day, metadata: { stage_id: won_stage.id })
  end

  it 'groups terminal events by current card assignees' do
    result = described_class.new(**report_query_options).call

    expect(result).to include(hash_including(agent_id: agent.id, won: 1, lost: 0))
  end

  it 'honors the agent filter' do
    result = described_class.new(**report_query_options(agent_ids: [administrator.id])).call

    expect(result).to be_empty
  end
end
