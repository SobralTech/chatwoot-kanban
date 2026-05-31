require 'rails_helper'

RSpec.describe KanbanBoard do
  describe 'defaults' do
    it 'disables automatic card creation for new boards' do
      board = described_class.new

      expect(board.auto_create_cards_from_conversations).to be(false)
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

    it 'allows boards without a default stage' do
      board = build(:kanban_board, account: create(:account), default_stage: nil)

      expect(board).to be_valid
    end

    it 'allows an active default stage from the same board' do
      board = create(:kanban_board)
      stage = create(:kanban_stage, account: board.account, kanban_board: board)

      board.default_stage = stage

      expect(board).to be_valid
    end

    it 'rejects a default stage from another board' do
      account = create(:account)
      board = create(:kanban_board, account: account)
      other_board = create(:kanban_board, account: account)
      stage = create(:kanban_stage, account: account, kanban_board: other_board)

      board.default_stage = stage

      expect(board).not_to be_valid
      expect(board.errors[:default_stage]).to be_present
    end

    it 'rejects a default stage from another account' do
      board = create(:kanban_board)
      other_account = create(:account)
      other_board = create(:kanban_board, account: other_account)
      stage = create(:kanban_stage, account: other_account, kanban_board: other_board)

      board.default_stage = stage

      expect(board).not_to be_valid
      expect(board.errors[:default_stage]).to be_present
    end

    it 'rejects an inactive default stage' do
      board = create(:kanban_board)
      stage = create(:kanban_stage, account: board.account, kanban_board: board, active: false)

      board.default_stage = stage

      expect(board).not_to be_valid
      expect(board.errors[:default_stage]).to be_present
    end
  end
end
