require 'rails_helper'

RSpec.describe KanbanBoardEntryRules::ConversationFilter do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:first_agent) { create(:user, account: account, role: :agent) }
  let(:second_agent) { create(:user, account: account, role: :agent) }
  let(:first_team) { create(:team, account: account) }
  let(:second_team) { create(:team, account: account) }

  let!(:empty_conversation) do
    create(:conversation, account: account, inbox: inbox, assignee: nil, team: nil, priority: nil).tap do |conversation|
      conversation.update_column(:cached_label_list, nil) # rubocop:disable Rails/SkipsModelValidations
    end
  end
  let!(:first_conversation) do
    create(:conversation, account: account, inbox: inbox, assignee: first_agent, team: first_team, priority: 'urgent').tap do |conversation|
      conversation.update_column(:cached_label_list, 'vip, urgent') # rubocop:disable Rails/SkipsModelValidations
    end
  end
  let!(:second_conversation) do
    create(:conversation, account: account, inbox: inbox, assignee: second_agent, team: second_team, priority: 'low').tap do |conversation|
      conversation.update_column(:cached_label_list, ' billing , vip ') # rubocop:disable Rails/SkipsModelValidations
    end
  end

  it 'selects the same conversations as the Ruby matcher for every supported condition' do
    condition_sets.each do |conditions|
      rule = KanbanBoardEntryRule.new(conditions: conditions)
      sql_ids = described_class.apply(conversation_scope, rule).order(:id).pluck(:id)
      ruby_ids = conversations.select { |conversation| KanbanBoardEntryRules::Matcher.match?(conversation, rule) }.map(&:id).sort

      expect(sql_ids).to eq(ruby_ids), "expected SQL and Ruby to agree for #{conditions.inspect}"
    end
  end

  it 'returns nil when a condition needs the Ruby fallback' do
    rule = KanbanBoardEntryRule.new(
      conditions: [{ attribute_key: 'future_attribute', filter_operator: 'is_one_of', values: ['value'] }]
    )

    expect(described_class.apply(conversation_scope, rule)).to be_nil
  end

  def conversations
    [empty_conversation, first_conversation, second_conversation]
  end

  def conversation_scope
    Conversation.where(id: conversations.map(&:id))
  end

  def condition_sets
    label_condition_sets + assignee_condition_sets + team_condition_sets + priority_condition_sets + combined_condition_sets
  end

  def label_condition_sets
    [
      [{ attribute_key: 'labels', filter_operator: 'includes_any', values: ['vip'] }],
      [{ attribute_key: 'labels', filter_operator: 'includes_any', values: ['none'] }],
      [{ attribute_key: 'labels', filter_operator: 'includes_all', values: %w[vip urgent] }],
      [{ attribute_key: 'labels', filter_operator: 'includes_all', values: %w[vip none] }],
      [{ attribute_key: 'labels', filter_operator: 'not_includes', values: ['vip'] }],
      [{ attribute_key: 'labels', filter_operator: 'not_includes', values: ['none'] }]
    ]
  end

  def assignee_condition_sets
    [
      [{ attribute_key: 'assignee_id', filter_operator: 'is_one_of', values: [first_agent.id.to_s] }],
      [{ attribute_key: 'assignee_id', filter_operator: 'is_one_of', values: ['none'] }],
      [{ attribute_key: 'assignee_id', filter_operator: 'is_not_one_of', values: [first_agent.id.to_s] }],
      [{ attribute_key: 'assignee_id', filter_operator: 'is_not_one_of', values: [first_agent.id.to_s, 'none'] }],
      [{ attribute_key: 'assignee_id', filter_operator: 'is_one_of', values: ['not-a-number'] }],
      [{ attribute_key: 'assignee_id', filter_operator: 'is_not_one_of', values: ['not-a-number'] }]
    ]
  end

  def team_condition_sets
    [
      [{ attribute_key: 'team_id', filter_operator: 'is_one_of', values: [first_team.id.to_s] }],
      [{ attribute_key: 'team_id', filter_operator: 'is_not_one_of', values: [second_team.id.to_s] }]
    ]
  end

  def priority_condition_sets
    [
      [{ attribute_key: 'priority', filter_operator: 'is_one_of', values: ['urgent'] }],
      [{ attribute_key: 'priority', filter_operator: 'is_one_of', values: ['none'] }],
      [{ attribute_key: 'priority', filter_operator: 'is_not_one_of', values: %w[urgent none] }]
    ]
  end

  def combined_condition_sets
    [
      [
        { attribute_key: 'labels', filter_operator: 'includes_any', values: ['vip'] },
        { attribute_key: 'priority', filter_operator: 'is_one_of', values: ['urgent'] }
      ]
    ]
  end
end
