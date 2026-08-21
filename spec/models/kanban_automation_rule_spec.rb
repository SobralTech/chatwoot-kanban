require 'rails_helper'

RSpec.describe KanbanAutomationRule do
  describe 'defaults' do
    it 'starts disabled and in dry run mode' do
      rule = create(:kanban_automation_rule)

      expect(rule).not_to be_active
      expect(rule).to be_dry_run
    end
  end

  describe 'validations' do
    it 'rejects an unknown event' do
      rule = build(:kanban_automation_rule, event_name: 'conversation_created')

      expect(rule).not_to be_valid
      expect(rule.errors[:event_name]).to be_present
    end

    it 'rejects an unknown condition attribute' do
      rule = build(
        :kanban_automation_rule,
        conditions: [{ attribute_key: 'unknown', filter_operator: 'equal_to', values: ['value'] }]
      )

      expect(rule).not_to be_valid
      expect(rule.errors[:conditions].join).to include('attribute_key')
    end

    it 'rejects an unknown filter operator' do
      rule = build(
        :kanban_automation_rule,
        conditions: [{ attribute_key: 'priority', filter_operator: 'contains', values: ['high'] }]
      )

      expect(rule).not_to be_valid
      expect(rule.errors[:conditions].join).to include('filter_operator')
    end

    it 'rejects an unknown action' do
      rule = build(
        :kanban_automation_rule,
        actions: [{ action_name: 'resolve_conversation', action_params: {} }]
      )

      expect(rule).not_to be_valid
      expect(rule.errors[:actions].join).to include('action_name')
    end

    it 'rejects a stage from another board' do
      board = create(:kanban_board)
      other_board = create(:kanban_board, account: board.account)
      stage = create(:kanban_stage, account: board.account, kanban_board: other_board)
      rule = build(
        :kanban_automation_rule,
        account: board.account,
        kanban_board: board,
        actions: [{ action_name: 'move_to_stage', action_params: { stage_id: stage.id } }]
      )

      expect(rule).not_to be_valid
      expect(rule.errors[:actions].join).to include('stage_id')
    end

    it 'rejects a move to a terminal stage' do
      board = create(:kanban_board)
      terminal_stage = create(:kanban_stage, account: board.account, kanban_board: board)
      board.update!(won_stage: terminal_stage)
      rule = build(
        :kanban_automation_rule,
        account: board.account,
        kanban_board: board,
        actions: [{ action_name: 'move_to_stage', action_params: { stage_id: terminal_stage.id } }]
      )

      expect(rule).not_to be_valid
      expect(rule.errors[:actions].join).to include('terminal')
    end

    it 'rejects more than ten actions' do
      actions = Array.new(11) do
        { action_name: 'set_priority', action_params: { priority: 'high' } }
      end
      rule = build(:kanban_automation_rule, actions: actions)

      expect(rule).not_to be_valid
      expect(rule.errors[:actions].join).to include('10')
    end

    it 'returns validation errors instead of raising for malformed collections' do
      rule = build(:kanban_automation_rule, conditions: { attribute_key: 'priority' })

      expect { rule.valid? }.not_to raise_error
      expect(rule.errors[:conditions]).to be_present
    end

    # The lookups used to return what `errors.add` hands back, and the caller then
    # asked that ActiveModel::Error for its id.
    [{}, { stage_id: 'abc' }, { stage_id: nil }].each do |action_params|
      it "reports rather than raises for move_to_stage with #{action_params.inspect}" do
        board = create(:kanban_board)
        rule = build(
          :kanban_automation_rule,
          account: board.account,
          kanban_board: board,
          actions: [{ action_name: 'move_to_stage', action_params: action_params }]
        )

        expect { rule.valid? }.not_to raise_error
        expect(rule.errors[:actions].join).to include('stage_id')
      end
    end

    it 'reports rather than raises for create_card_in_board with a bad board id' do
      board = create(:kanban_board)
      rule = build(
        :kanban_automation_rule,
        account: board.account,
        kanban_board: board,
        actions: [{ action_name: 'create_card_in_board', action_params: { kanban_board_id: 'abc', stage_id: 'abc' } }]
      )

      expect { rule.valid? }.not_to raise_error
      expect(rule.errors[:actions].join).to include('kanban_board_id')
    end
  end
end
