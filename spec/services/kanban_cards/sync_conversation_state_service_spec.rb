require 'rails_helper'

RSpec.describe KanbanCards::SyncConversationStateService do
  let(:account) { create(:account) }
  let(:board) { create(:kanban_board, account: account) }
  let(:stage) { create(:kanban_stage, account: account, kanban_board: board) }
  let(:conversation) { create(:conversation, account: account) }
  let(:state) do
    create(
      :conversation_kanban_state,
      account: account,
      conversation: conversation,
      kanban_board: board,
      kanban_stage: stage,
      position: 3
    )
  end

  describe '#sync!' do
    it 'creates a mirrored conversation-origin kanban card' do
      expect { described_class.new(state).sync! }.to change(KanbanCard, :count).by(1)

      expect(mirrored_card).to be_present
      expect(mirrored_card).to be_conversation
    end

    it 'copies all required fields from the legacy state' do
      described_class.new(state).sync!

      expect(mirrored_card).to have_attributes(
        account_id: conversation.account_id,
        kanban_board_id: state.kanban_board_id,
        kanban_stage_id: state.kanban_stage_id,
        contact_id: conversation.contact_id,
        inbox_id: conversation.inbox_id,
        conversation_id: state.conversation_id,
        subject: nil,
        normalized_subject: nil,
        origin: 'conversation',
        position: state.position,
        active: true
      )
    end

    it 'is idempotent' do
      described_class.new(state).sync!

      expect { described_class.new(state).sync! }.not_to change(KanbanCard, :count)
    end

    it 'mirrors stage changes' do
      new_stage = create(:kanban_stage, account: account, kanban_board: board)
      described_class.new(state).sync!
      mirrored_card.update_column(:stage_entered_at, 2.days.ago.change(usec: 0)) # rubocop:disable Rails/SkipsModelValidations

      state.update!(kanban_stage: new_stage)
      travel_to(Time.zone.parse('2026-06-09 12:00:00 UTC')) do
        described_class.new(state).sync!
      end

      expect(mirrored_card.reload).to have_attributes(
        kanban_stage: new_stage,
        stage_entered_at: Time.zone.parse('2026-06-09 12:00:00 UTC')
      )
    end

    it 'mirrors position changes' do
      described_class.new(state).sync!
      previous_stage_entered_at = 2.days.ago.change(usec: 0)
      mirrored_card.update_column(:stage_entered_at, previous_stage_entered_at) # rubocop:disable Rails/SkipsModelValidations

      state.update!(position: 7)
      described_class.new(state).sync!

      expect(mirrored_card.reload.position).to eq(7)
      expect(mirrored_card.stage_entered_at).to eq(previous_stage_entered_at)
    end

    it 'reactivates an existing inactive mirrored card' do
      inactive_card = create(
        :kanban_card,
        :conversation_origin,
        account: account,
        kanban_board: board,
        kanban_stage: stage,
        conversation: conversation,
        active: false
      )

      expect { described_class.new(state).sync! }.not_to change(KanbanCard, :count)
      expect(inactive_card.reload).to be_active
    end

    it 'does not modify manual cards during sync' do
      manual_card = create(
        :kanban_card,
        account: account,
        kanban_board: board,
        kanban_stage: stage,
        contact: conversation.contact,
        inbox: conversation.inbox
      )
      original_attributes = manual_attributes(manual_card)

      described_class.new(state).sync!

      expect(manual_attributes(manual_card.reload)).to eq(original_attributes)
    end

    it 'handles unique-index contention by updating the existing conversation-origin card' do
      service = described_class.new(state)
      new_card = build(:kanban_card, :conversation_origin, conversation: conversation)
      contended_card = create(
        :kanban_card,
        :conversation_origin,
        account: account,
        kanban_board: board,
        kanban_stage: stage,
        conversation: conversation,
        position: 1
      )

      allow(service).to receive(:mirrored_card).and_return(nil, contended_card)
      allow(KanbanCard).to receive(:new).and_return(new_card)
      allow(new_card).to receive(:save!).and_raise(ActiveRecord::RecordNotUnique)

      service.sync!

      expect(contended_card.reload.position).to eq(state.position)
    end
  end

  describe '#deactivate!' do
    it 'soft-deletes the mirrored card' do
      card = described_class.new(state).sync!

      described_class.new(state).deactivate!

      expect(card.reload).not_to be_active
    end

    it 'is safe when the mirrored card does not exist' do
      expect { described_class.new(state).deactivate! }.not_to raise_error
    end

    it 'does not modify manual cards during deactivation' do
      manual_card = create(
        :kanban_card,
        account: account,
        kanban_board: board,
        kanban_stage: stage,
        contact: conversation.contact,
        inbox: conversation.inbox
      )
      original_attributes = manual_attributes(manual_card)

      described_class.new(state).deactivate!

      expect(manual_attributes(manual_card.reload)).to eq(original_attributes)
    end
  end

  describe 'associations' do
    it 'adds useful associations without destructive callbacks' do
      expect(KanbanBoard.reflect_on_association(:kanban_cards).options[:dependent]).to be_nil
      expect(KanbanStage.reflect_on_association(:kanban_cards).options[:dependent]).to be_nil
      expect(Conversation.reflect_on_association(:kanban_cards).options[:dependent]).to be_nil
    end
  end

  def mirrored_card
    KanbanCard.conversation.find_by(kanban_board: board, conversation: conversation)
  end

  def manual_attributes(card)
    card.attributes.slice('kanban_stage_id', 'position', 'active', 'origin', 'subject', 'normalized_subject')
  end
end
