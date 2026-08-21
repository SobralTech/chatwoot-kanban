require 'rails_helper'

RSpec.describe KanbanAutomations::RuleMatcher do
  let(:account) { create(:account) }
  let(:board) { create(:kanban_board, account: account) }
  let(:stage) { create(:kanban_stage, account: account, kanban_board: board) }
  let(:contact) { create(:contact, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:card) do
    create(
      :kanban_card,
      account: account,
      kanban_board: board,
      kanban_stage: stage,
      contact: contact,
      inbox: inbox,
      priority: :high
    )
  end

  before do
    card.update_labels(%w[vip renewal])
  end

  describe '.match?' do
    it 'matches equality operators' do
      expect(match_condition('priority', 'equal_to', ['high'])).to be(true)
      expect(match_condition('priority', 'not_equal_to', ['low'])).to be(true)
    end

    it 'matches presence operators' do
      expect(match_condition('priority', 'is_present', [])).to be(true)
      expect(match_condition('reason_id', 'is_not_present', [])).to be(true)
    end

    it 'matches numeric operators' do
      expect(match_condition('stage_id', 'greater_than', [stage.id - 1])).to be(true)
      expect(match_condition('stage_id', 'less_than', [stage.id + 1])).to be(true)
    end

    it 'matches collection operators' do
      expect(match_condition('priority', 'is_one_of', %w[low high])).to be(true)
      expect(match_condition('labels', 'includes', ['vip'])).to be(true)
    end

    it 'calculates hours in the current stage' do
      card.update_column(:stage_entered_at, 3.hours.ago) # rubocop:disable Rails/SkipsModelValidations

      expect(match_condition('hours_in_stage', 'greater_than', [2])).to be(true)
    end

    it 'matches the derived open-card condition' do
      create(
        :kanban_card,
        account: account,
        kanban_board: board,
        kanban_stage: stage,
        contact: contact,
        inbox: inbox,
        subject: 'Another opportunity'
      )

      expect(match_condition('contact_has_open_card', 'equal_to', [true])).to be(true)
    end

    it 'does not match a card that fails one condition' do
      expect(match_condition('priority', 'equal_to', ['low'])).to be(false)
    end

    it 'requires all conditions to match' do
      expect(
        match_conditions(
          [
            { attribute_key: 'priority', filter_operator: 'equal_to', values: ['high'] },
            { attribute_key: 'origin', filter_operator: 'equal_to', values: ['conversation'] }
          ]
        )
      ).to be(false)
    end
  end

  def match_condition(attribute_key, filter_operator, values)
    match_conditions([{ attribute_key: attribute_key, filter_operator: filter_operator, values: values }])
  end

  def match_conditions(conditions)
    rule = build(:kanban_automation_rule, account: account, kanban_board: board, conditions: conditions)
    described_class.match?(card, rule)
  end
end
