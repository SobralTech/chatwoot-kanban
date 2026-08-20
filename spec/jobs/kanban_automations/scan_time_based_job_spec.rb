require 'rails_helper'

RSpec.describe KanbanAutomations::ScanTimeBasedJob do
  let(:account) { create(:account) }
  let(:board) { create(:kanban_board, account: account) }
  let(:stage) { create(:kanban_stage, account: account, kanban_board: board) }
  let(:card) { create(:kanban_card, account: account, kanban_board: board, kanban_stage: stage) }
  let(:rule) do
    create(
      :kanban_automation_rule,
      account: account,
      kanban_board: board,
      active: true,
      event_name: 'card_stalled',
      conditions: [{ attribute_key: 'hours_in_stage', filter_operator: 'greater_than', values: [1] }]
    )
  end

  it 'enqueues a matching card once across repeated scans on the same day' do
    card.update_column(:stage_entered_at, 2.hours.ago) # rubocop:disable Rails/SkipsModelValidations
    rule
    allow(Redis::Alfred).to receive(:set).and_return(true, false, false)

    expect(KanbanAutomations::RunRulesJob).to receive(:perform_later).once.with(
      card.id, [rule.id], 'card_stalled', {}
    )

    3.times { described_class.perform_now }
  end
end
