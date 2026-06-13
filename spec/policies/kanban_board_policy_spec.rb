require 'rails_helper'

RSpec.describe KanbanBoardPolicy, type: :policy do
  subject(:policy) { described_class }

  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_user) { create(:user) }
  let(:admin_context) { { user: administrator, account: account, account_user: administrator.account_users.find_by(account: account) } }
  let(:agent_context) { { user: agent, account: account, account_user: agent.account_users.find_by(account: account) } }
  let(:other_context) { { user: other_user, account: account, account_user: nil } }

  # rubocop:disable RSpec/RepeatedExample
  permissions :index?, :show? do
    it { is_expected.to permit(admin_context, KanbanBoard) }
    it { is_expected.to permit(agent_context, KanbanBoard) }
  end

  permissions :create? do
    it { is_expected.to permit(admin_context, KanbanBoard) }
    it { is_expected.to permit(agent_context, KanbanBoard) }
    it { is_expected.not_to permit(other_context, KanbanBoard) }
  end

  permissions :update?, :destroy? do
    it { is_expected.to permit(admin_context, KanbanBoard) }
    it { is_expected.not_to permit(agent_context, KanbanBoard) }
  end
  # rubocop:enable RSpec/RepeatedExample

  describe '#visible?' do
    subject(:visible?) { described_class.new(context, board).visible? }

    let(:board) { create(:kanban_board, account: account) }

    context 'when user is administrator' do
      let(:context) { admin_context }

      it 'allows all active boards' do
        expect(visible?).to be true
      end

      it 'allows selected_agents boards without membership' do
        board.update!(visibility_mode: 'selected_agents')
        expect(visible?).to be true
      end

      it 'rejects inactive boards' do
        board.update!(active: false)
        expect(visible?).to be false
      end
    end

    context 'when user is agent' do
      let(:context) { agent_context }

      it 'allows all_agents boards' do
        expect(visible?).to be true
      end

      it 'allows selected_agents boards when member' do
        board.update!(visibility_mode: 'selected_agents')
        create(:kanban_board_member, account: account, kanban_board: board, user: agent)
        expect(visible?).to be true
      end

      it 'rejects selected_agents boards without membership' do
        board.update!(visibility_mode: 'selected_agents')
        expect(visible?).to be false
      end

      it 'rejects inactive boards' do
        board.update!(active: false)
        expect(visible?).to be false
      end
    end

    context 'when user is outside the account' do
      let(:context) { other_context }

      it 'rejects all boards' do
        expect(visible?).to be false
      end
    end
  end

  describe 'Scope' do
    subject(:resolved) { described_class::Scope.new(context, KanbanBoard.all).resolve }

    let!(:all_agents_board) { create(:kanban_board, account: account, visibility_mode: 'all_agents', name: 'Public') }
    let!(:selected_board) { create(:kanban_board, account: account, visibility_mode: 'selected_agents', name: 'Restricted') }
    let!(:inactive_board) { create(:kanban_board, account: account, active: false, name: 'Inactive') }
    let!(:other_account_board) { create(:kanban_board, visibility_mode: 'all_agents', name: 'Other') }

    context 'when administrator' do
      let(:context) { admin_context }

      it 'returns all active boards in the account' do
        expect(resolved).to include(all_agents_board, selected_board)
        expect(resolved).not_to include(inactive_board, other_account_board)
      end
    end

    context 'when agent is member of selected board' do
      let(:context) { agent_context }

      before do
        create(:kanban_board_member, account: account, kanban_board: selected_board, user: agent)
      end

      it 'returns all_agents and member selected_agents boards' do
        expect(resolved).to include(all_agents_board, selected_board)
        expect(resolved).not_to include(inactive_board, other_account_board)
      end
    end

    context 'when agent is not member of selected board' do
      let(:context) { agent_context }

      it 'returns only all_agents boards' do
        expect(resolved).to contain_exactly(all_agents_board)
      end
    end

    context 'when user is outside the account' do
      let(:context) { other_context }

      it 'returns no boards' do
        expect(resolved).to be_empty
      end
    end
  end
end
