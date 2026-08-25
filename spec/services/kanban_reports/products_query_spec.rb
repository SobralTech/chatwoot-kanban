require 'rails_helper'

RSpec.describe KanbanReports::ProductsQuery, type: :service do
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
    KanbanCardProduct.create!(account: account, kanban_card: card, sku: 'SKU-1', name: 'Plan', unit_price: 25, quantity: 2)
    report_event(card: card, event_type: 'won', at: report_start + 1.day, metadata: { stage_id: won_stage.id })
  end

  it 'includes products from won cards only' do
    lost_card = create(:kanban_card, account: account, kanban_board: board, kanban_stage: lost_stage, inbox: inbox)
    KanbanCardProduct.create!(account: account, kanban_card: lost_card, sku: 'SKU-LOST', name: 'Lost plan', unit_price: 10,
                              quantity: 1)
    report_event(card: lost_card, event_type: 'lost', at: report_start + 1.day, metadata: { stage_id: lost_stage.id })

    result = described_class.new(**report_query_options).call

    expect(result).to include(hash_including(sku: 'SKU-1', quantity: 2, revenue: '50.0', cards_count: 1))
    expect(result).not_to include(hash_including(sku: 'SKU-LOST'))
  end
end
