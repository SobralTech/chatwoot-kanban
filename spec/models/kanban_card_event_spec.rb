require 'rails_helper'

RSpec.describe KanbanCardEvent do
  let(:account) { create(:account) }
  let(:card) { create(:kanban_card, account: account) }

  it 'requires an event type' do
    event = described_class.new(account: account, kanban_card: card, kanban_board: card.kanban_board)

    expect(event).not_to be_valid
    expect(event.errors).to include(:event_type)
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

  it 'allows a board scoped event without a card' do
    event = build(
      :kanban_card_event,
      account: account,
      kanban_card: nil,
      kanban_board: card.kanban_board,
      event_type: 'card_deleted'
    )

    expect(event).to be_valid
  end
end
