require 'rails_helper'

RSpec.describe KanbanBoard do
  describe 'defaults' do
    it 'disables automatic card creation for new boards' do
      board = described_class.new

      expect(board.auto_create_cards_from_conversations).to be(false)
    end

    it 'keeps new boards visible to all agents' do
      board = described_class.new

      expect(board.visibility_mode).to eq('all_agents')
    end

    it 'keeps persisted boards visible to all agents when visibility is not specified' do
      board = create(:kanban_board)

      expect(board.visibility_mode).to eq('all_agents')
    end
  end

  describe 'validations' do
    it 'prevents duplicate active names inside an account' do
      account = create(:account)
      create(:kanban_board, account: account, name: 'Sales')

      board = build(:kanban_board, account: account, name: 'Sales')

      expect(board).not_to be_valid
      expect(board.errors[:name]).to be_present
    end

    it 'allows the same name when the previous board is inactive' do
      account = create(:account)
      create(:kanban_board, account: account, name: 'Sales', active: false)

      board = build(:kanban_board, account: account, name: 'Sales')

      expect(board).to be_valid
    end

    it 'allows the same name in another account' do
      create(:kanban_board, account: create(:account), name: 'Sales')
      other_account = create(:account)

      board = build(:kanban_board, account: other_account, name: 'Sales')

      expect(board).to be_valid
    end

    it 'accepts supported visibility modes' do
      account = create(:account)

      described_class::VISIBILITY_MODES.each do |visibility_mode|
        board = build(:kanban_board, account: account, visibility_mode: visibility_mode)

        expect(board).to be_valid
      end
    end

    it 'rejects unsupported visibility modes' do
      board = build(:kanban_board, account: create(:account), visibility_mode: 'private')

      expect(board).not_to be_valid
      expect(board.errors[:visibility_mode]).to be_present
    end
  end

  describe 'associations' do
    it 'exposes board members as visible users' do
      board = create(:kanban_board)
      user = create(:user, account: board.account)
      create(:kanban_board_member, account: board.account, kanban_board: board, user: user)

      expect(board.kanban_board_members.count).to eq(1)
      expect(board.visible_users).to contain_exactly(user)
    end
  end
end
