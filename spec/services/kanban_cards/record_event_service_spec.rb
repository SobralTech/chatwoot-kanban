require 'rails_helper'

RSpec.describe KanbanCards::RecordEventService do
  let(:account) { create(:account) }
  let(:card) { create(:kanban_card, account: account) }
  let(:user) { create(:user, account: account) }

  it 'records the card scope, author, type, metadata, and timestamp' do
    created_at = Time.zone.parse('2026-08-18 12:00:00 UTC')

    expect do
      described_class.call(
        card: card,
        event_type: 'stage_changed',
        user: user,
        metadata: { from_stage_id: 1, to_stage_id: 2 },
        created_at: created_at
      )
    end.to change(KanbanCardEvent, :count).by(1)

    event = KanbanCardEvent.last
    expect(event).to have_attributes(
      account_id: account.id,
      kanban_card_id: card.id,
      kanban_board_id: card.kanban_board_id,
      user_id: user.id,
      event_type: 'stage_changed',
      metadata: { 'from_stage_id' => 1, 'to_stage_id' => 2 },
      created_at: created_at
    )
  end

  it 'records system events without a user' do
    described_class.call(card: card, event_type: 'card_created')

    expect(KanbanCardEvent.last.user_id).to be_nil
    expect(KanbanCardEvent.last.metadata).to eq({})
  end
end
