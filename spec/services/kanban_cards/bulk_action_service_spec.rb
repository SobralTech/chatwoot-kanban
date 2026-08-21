require 'rails_helper'

RSpec.describe KanbanCards::BulkActionService do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:kanban_board) { create(:kanban_board, account: account) }
  let(:regular_stage) { create(:kanban_stage, account: account, kanban_board: kanban_board) }
  let(:inbox) { create(:inbox, account: account) }

  before do
    create(:inbox_member, user: agent, inbox: inbox)
  end

  describe '#perform!' do
    it 'returns a partial result when one card violates a transition rule' do
      won_stage = create(:kanban_stage, account: account, kanban_board: kanban_board, name: 'Won')
      lost_stage = create(:kanban_stage, account: account, kanban_board: kanban_board, name: 'Lost')
      kanban_board.update!(won_stage_id: won_stage.id, lost_stage_id: lost_stage.id, lost_reason_required: true)
      reason = KanbanReason.create!(account: account, kanban_board: kanban_board, title: 'No response', reason_type: :lost)

      won_card = create_card(stage: won_stage, subject: 'Won card')
      regular_card = create_card(stage: regular_stage, subject: 'Regular card')

      result = service(
        operation: :lose,
        card_ids: [won_card.id, regular_card.id],
        payload: { kanban_reason_id: reason.id }
      ).perform!

      expect(result.succeeded).to eq([regular_card.id])
      expect(result.failed).to eq([{ id: won_card.id, error: 'direct_won_lost_transition_not_allowed' }])
      expect(won_card.reload.kanban_stage_id).to eq(won_stage.id)
      expect(regular_card.reload).to have_attributes(kanban_stage_id: lost_stage.id, kanban_reason_id: reason.id)
    end

    it 'authorizes every card independently' do
      visible_card = create_card(stage: regular_stage, subject: 'Visible card')
      hidden_inbox = create(:inbox, account: account)
      hidden_card = create_card(stage: regular_stage, subject: 'Hidden card', inbox: hidden_inbox)

      result = service(
        operation: :priority,
        card_ids: [visible_card.id, hidden_card.id],
        payload: { priority: 'high' }
      ).perform!

      expect(result.succeeded).to eq([visible_card.id])
      expect(result.failed).to eq([{ id: hidden_card.id, error: 'not_authorized' }])
      expect(visible_card.reload.priority).to eq('high')
      expect(hidden_card.reload.priority).to be_nil
    end

    it 'triggers the automation event the transition resolved, and only for moves' do
      target_stage = create(:kanban_stage, account: account, kanban_board: kanban_board, name: 'Negotiation')
      moved_card = create_card(stage: regular_stage, subject: 'Moved card')
      other_card = create_card(stage: regular_stage, subject: 'Reprioritised card')

      allow(KanbanAutomations::TriggerService).to receive(:call)

      service(operation: :move, card_ids: [moved_card.id], payload: { kanban_stage_id: target_stage.id }).perform!
      service(operation: :priority, card_ids: [other_card.id], payload: { priority: 'high' }).perform!

      expect(KanbanAutomations::TriggerService).to have_received(:call).once
                                                                       .with(hash_including(event_name: 'stage_changed'))
    end

    it 'rejects more than the maximum number of cards' do
      card_ids = (1..(KanbanCards::BulkActionRequest::MAX_CARDS + 1)).to_a

      expect do
        service(operation: :priority, card_ids: card_ids, payload: { priority: 'high' }).perform!
      end.to raise_error(KanbanCards::BulkActionRequest::Error, 'bulk_action_limit_exceeded')
    end

    it 'fails the whole request instead of every card when the payload is invalid' do
      cards = Array.new(2) { create_card(stage: regular_stage, subject: 'Opportunity') }

      expect do
        service(operation: :assign, card_ids: cards.map(&:id), payload: { assignee_ids: [0] }).perform!
      end.to raise_error(KanbanCards::BulkActionRequest::Error, 'unknown_assignees')

      expect(cards.map { |card| card.reload.kanban_card_assignees.count }).to all(be_zero)
    end
  end

  def service(operation:, card_ids:, payload: {})
    described_class.new(
      user: agent,
      kanban_board: kanban_board,
      operation: operation,
      card_ids: card_ids,
      payload: payload
    )
  end

  def create_card(stage:, subject:, inbox: self.inbox)
    create(
      :kanban_card,
      account: account,
      kanban_board: kanban_board,
      kanban_stage: stage,
      contact: create(:contact, account: account),
      inbox: inbox,
      subject: subject,
      position: 1
    )
  end
end
