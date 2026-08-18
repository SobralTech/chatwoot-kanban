require 'rails_helper'

RSpec.describe KanbanCardEvent do
  let(:account) { create(:account) }
  let(:card) { create(:kanban_card, account: account) }

  it 'requires the event identity fields' do
    event = described_class.new(metadata: {})

    expect(event).not_to be_valid
    expect(event.errors).to include(:account_id, :kanban_card_id, :kanban_board_id, :event_type)
  end

  it 'allows empty metadata and system events without a user' do
    event = build(
      :kanban_card_event,
      account: account,
      kanban_card: card,
      kanban_board: card.kanban_board,
      user: nil,
      metadata: {}
    )

    expect(event).to be_valid
  end

  it 'rejects metadata that is not a hash' do
    event = build(:kanban_card_event, account: account, kanban_card: card, metadata: [])

    expect(event).not_to be_valid
    expect(event.errors[:metadata]).to include('must be a hash')
  end
end
