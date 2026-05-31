require 'rails_helper'

RSpec.describe KanbanBoard do
  describe 'defaults' do
    it 'disables automatic card creation for new boards' do
      board = described_class.new

      expect(board.auto_create_cards_from_conversations).to be(false)
    end

    it 'enables opportunity card reads for new boards' do
      board = described_class.new

      expect(board.use_opportunity_card_reads).to be(true)
    end

    it 'keeps explicitly disabled opportunity card reads for persisted boards' do
      board = create(:kanban_board, use_opportunity_card_reads: false)

      board.update!(name: 'Legacy Sales')

      expect(board.reload.use_opportunity_card_reads).to be(false)
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
  end
end
