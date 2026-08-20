require 'rails_helper'

RSpec.describe KanbanAutomations::TriggerService do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:board) { create(:kanban_board, account: account) }
  let(:stage) { create(:kanban_stage, account: account, kanban_board: board) }
  let(:card) { create(:kanban_card, account: account, kanban_board: board, kanban_stage: stage) }

  before { clear_enqueued_jobs }

  describe '.call' do
    it 'enqueues active rules in position order' do
      later_rule = create_rule(position: 2)
      first_rule = create_rule(position: 1)

      expect do
        described_class.call(card: card, event_name: 'card_created', user: nil)
      end.to have_enqueued_job(KanbanAutomations::RunRulesJob)
        .with(card.id, [first_rule.id, later_rule.id], 'card_created', { 'automation_depth' => 0 })
        .on_queue('low')
    end

    it 'does not enqueue inactive rules' do
      create_rule(active: false)

      expect do
        described_class.call(card: card, event_name: 'card_created', user: nil)
      end.not_to have_enqueued_job(KanbanAutomations::RunRulesJob)
    end

    it 'stops at the maximum automation depth' do
      create_rule
      clear_enqueued_jobs

      expect do
        result = described_class.call(
          card: card,
          event_name: 'card_created',
          user: nil,
          context: { automation_depth: 2 }
        )
        expect(result).to eq(:depth_exceeded)
      end.not_to have_enqueued_job(KanbanAutomations::RunRulesJob)
    end
  end

  describe KanbanAutomations::RunRulesJob do
    it 'stops after the first matching rule marked stop_after_match' do
      first_rule = create_rule(position: 1, stop_after_match: true)
      second_rule = create_rule(position: 2)
      executor = instance_double(KanbanAutomations::ActionExecutor, perform: nil)

      allow(KanbanAutomations::RuleMatcher).to receive(:match?).and_return(true)
      allow(KanbanAutomations::ActionExecutor).to receive(:new).and_return(executor)

      described_class.perform_now(card.id, [first_rule.id, second_rule.id], 'card_created', {})

      expect(KanbanAutomations::ActionExecutor).to have_received(:new).once
      expect(KanbanAutomations::ActionExecutor).to have_received(:new).with(
        card: an_instance_of(KanbanCard), rule: first_rule, context: {}
      )
    end
  end

  def create_rule(position: 0, active: true, stop_after_match: false)
    create(
      :kanban_automation_rule,
      account: account,
      kanban_board: board,
      active: active,
      position: position,
      stop_after_match: stop_after_match
    )
  end
end
