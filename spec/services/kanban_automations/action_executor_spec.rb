require 'rails_helper'

RSpec.describe KanbanAutomations::ActionExecutor do
  let(:account) { create(:account) }
  let(:board) { create(:kanban_board, account: account) }
  let!(:source_stage) { create(:kanban_stage, account: account, kanban_board: board, position: 1) }
  let!(:target_stage) { create(:kanban_stage, account: account, kanban_board: board, position: 2) }
  let(:contact) { create(:contact, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:card) do
    create(
      :kanban_card,
      account: account,
      kanban_board: board,
      kanban_stage: source_stage,
      contact: contact,
      inbox: inbox,
      subject: 'Original opportunity'
    )
  end

  describe '.perform' do
    it 'moves a card to a regular stage and records a system event' do
      rule = create_rule(
        actions: [{ action_name: 'move_to_stage', action_params: { stage_id: target_stage.id } }]
      )

      described_class.perform(card: card, rule: rule)

      expect(card.reload.kanban_stage_id).to eq(target_stage.id)
      expect_event('stage_changed', rule)
    end

    it 'assigns the requested agents' do
      agent = create(:user, account: account, role: :agent)
      rule = create_rule(
        actions: [{ action_name: 'assign_agents', action_params: { agent_ids: [agent.id], mode: 'set' } }]
      )

      described_class.perform(card: card, rule: rule)

      expect(card.reload.kanban_card_assignees.pluck(:user_id)).to eq([agent.id])
      expect_event('assignees_changed', rule)
    end

    it 'sets priority' do
      rule = create_rule(actions: [{ action_name: 'set_priority', action_params: { priority: 'high' } }])

      described_class.perform(card: card, rule: rule)

      expect(card.reload.priority).to eq('high')
      expect_event('priority_changed', rule)
    end

    it 'adds and removes labels' do
      add_rule = create_rule(actions: [{ action_name: 'add_label', action_params: { labels: ['vip'] } }])
      described_class.perform(card: card, rule: add_rule)
      expect(card.reload.label_list).to include('vip')

      remove_rule = create_rule(actions: [{ action_name: 'remove_label', action_params: { labels: ['vip'] } }])
      described_class.perform(card: card, rule: remove_rule)

      expect(card.reload.label_list).not_to include('vip')
      expect_event('labels_changed', remove_rule)
    end

    it 'sets a due date' do
      rule = create_rule(actions: [{ action_name: 'set_due_at', action_params: { days: 3, business_days: false } }])

      travel_to Time.zone.parse('2026-08-20 10:00:00') do
        described_class.perform(card: card, rule: rule)
      end

      expect(card.reload.due_at).to be_within(1.second).of(Time.zone.parse('2026-08-23 10:00:00'))
      expect_event('due_at_changed', rule)
    end

    it 'creates a note and records the action' do
      rule = create_rule(
        actions: [{ action_name: 'create_note', action_params: { content: 'Follow up with {{ contact.name }}' } }]
      )

      described_class.perform(card: card, rule: rule)

      expect(card.kanban_card_notes.last.content).to eq("Follow up with #{contact.name}")
      expect_event('automation_action', rule, action_name: 'create_note')
    end

    it 'marks a card as lost' do
      lost_stage = create(:kanban_stage, account: account, kanban_board: board, position: 3)
      board.update!(lost_stage: lost_stage)
      reason = KanbanReason.create!(account: account, kanban_board: board, title: 'No response', reason_type: :lost)
      rule = create_rule(actions: [{ action_name: 'mark_as_lost', action_params: { reason_id: reason.id } }])

      described_class.perform(card: card, rule: rule)

      expect(card.reload).to have_attributes(kanban_stage_id: lost_stage.id, kanban_reason_id: reason.id)
      expect_event('lost', rule)
    end

    it 'creates a card in another board' do
      target_board = create(:kanban_board, account: account)
      target_board_stage = create(:kanban_stage, account: account, kanban_board: target_board, position: 1)
      rule = create_rule(
        actions: [
          {
            action_name: 'create_card_in_board',
            action_params: { kanban_board_id: target_board.id, stage_id: target_board_stage.id, subject: 'Copied card' }
          }
        ]
      )

      expect do
        described_class.perform(card: card, rule: rule)
      end.to change { KanbanCard.where(kanban_board: target_board).count }.by(1)

      created_card = KanbanCard.where(kanban_board: target_board).last
      expect(created_card.subject).to eq('Copied card')
      expect_event('automation_action', rule, action_name: 'create_card_in_board')
      expect(created_card.kanban_card_events.last.metadata['automation_rule_id']).to eq(rule.id)
    end

    it 'continues with the next action when one action fails' do
      tracker = instance_double(ChatwootExceptionTracker, capture_exception: nil)
      allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)
      rule = create_rule(
        actions: [
          { action_name: 'create_note', action_params: { content: '' } },
          { action_name: 'set_priority', action_params: { priority: 'high' } }
        ]
      )

      described_class.perform(card: card, rule: rule)

      expect(card.reload.priority).to eq('high')
      expect(tracker).to have_received(:capture_exception).once
      expect_event('automation_action', rule, action_name: 'create_note', status: 'failed')
    end

    it 'skips message actions without sending anything' do
      rule = create_rule(actions: [{ action_name: 'send_message', action_params: { content: 'Hello' } }])

      expect do
        described_class.perform(card: card, rule: rule)
      end.not_to change(Message, :count)

      expect_event('automation_action', rule, action_name: 'send_message', status: 'skipped')
    end

    it 'does not persist actions in dry-run mode' do
      rule = create_rule(
        dry_run: true,
        actions: [
          { action_name: 'move_to_stage', action_params: { stage_id: target_stage.id } },
          { action_name: 'set_priority', action_params: { priority: 'high' } },
          { action_name: 'add_label', action_params: { labels: ['vip'] } },
          { action_name: 'create_note', action_params: { content: 'Should not be saved' } }
        ]
      )

      expect do
        described_class.perform(card: card, rule: rule)
      end.not_to change(KanbanCardEvent, :count)

      expect(card.reload).to have_attributes(kanban_stage_id: source_stage.id, priority: nil, due_at: nil)
      expect(card.label_list).to be_empty
      expect(card.kanban_card_notes).to be_empty
    end
  end

  def create_rule(actions:, dry_run: false)
    create(
      :kanban_automation_rule,
      account: account,
      kanban_board: board,
      active: true,
      dry_run: dry_run,
      actions: actions
    )
  end

  # rubocop:disable Metrics/AbcSize
  def expect_event(event_type, rule, action_name: nil, status: nil)
    event = KanbanCardEvent.where(kanban_card: card, event_type: event_type).last
    expect(event).to be_present
    expect(event.user_id).to be_nil
    expect(event.metadata['automation_rule_id']).to eq(rule.id)
    expect(event.metadata['action_name']).to eq(action_name) if action_name
    expect(event.metadata['status']).to eq(status) if status
  end
  # rubocop:enable Metrics/AbcSize
end
