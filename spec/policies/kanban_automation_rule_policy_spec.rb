require 'rails_helper'

RSpec.describe KanbanAutomationRulePolicy, type: :policy do
  subject(:policy) { described_class }

  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:board) { create(:kanban_board, account: account) }
  let(:rule) { create(:kanban_automation_rule, account: account, kanban_board: board) }
  let(:administrator_context) do
    { user: administrator, account: account, account_user: administrator.account_users.find_by(account: account) }
  end
  let(:agent_context) do
    { user: agent, account: account, account_user: agent.account_users.find_by(account: account) }
  end

  permissions :index?, :create?, :update?, :destroy?, :toggle? do
    it 'permits administrators' do
      expect(policy).to permit(administrator_context, rule)
    end

    it 'rejects agents' do
      expect(policy).not_to permit(agent_context, rule)
    end
  end

  describe 'Scope' do
    subject(:resolved) { described_class::Scope.new(context, KanbanAutomationRule.all).resolve }

    let!(:account_rule) { rule }
    let!(:other_account_rule) { create(:kanban_automation_rule) }

    context 'when administrator' do
      let(:context) { administrator_context }

      it 'returns only rules from the current account' do
        expect(resolved).to contain_exactly(account_rule)
        expect(resolved).not_to include(other_account_rule)
      end
    end

    context 'when agent' do
      let(:context) { agent_context }

      it 'returns no rules' do
        expect(resolved).to be_empty
      end
    end
  end
end
