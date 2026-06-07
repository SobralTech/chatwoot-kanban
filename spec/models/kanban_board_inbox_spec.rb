require 'rails_helper'

RSpec.describe KanbanBoardInbox do
  describe 'validations' do
    it 'prevents duplicate inboxes inside a board' do
      board = create(:kanban_board)
      inbox = create(:inbox, account: board.account)
      create(:kanban_board_inbox, account: board.account, kanban_board: board, inbox: inbox)

      record = build(:kanban_board_inbox, account: board.account, kanban_board: board, inbox: inbox)

      expect(record).not_to be_valid
      expect(record.errors[:inbox_id]).to be_present
    end

    it 'rejects a record with an account different from the board account' do
      board = create(:kanban_board)
      other_account = create(:account)
      inbox = create(:inbox, account: other_account)

      record = build(:kanban_board_inbox, account: other_account, kanban_board: board, inbox: inbox)

      expect(record).not_to be_valid
      expect(record.errors[:account_id]).to be_present
    end

    it 'rejects a record with an account different from the inbox account' do
      board = create(:kanban_board)
      other_account = create(:account)
      inbox = create(:inbox, account: other_account)

      record = build(:kanban_board_inbox, account: board.account, kanban_board: board, inbox: inbox)

      expect(record).not_to be_valid
      expect(record.errors[:account_id]).to be_present
    end

    it 'accepts matching account for board and inbox' do
      board = create(:kanban_board)
      inbox = create(:inbox, account: board.account)

      record = build(:kanban_board_inbox, account: board.account, kanban_board: board, inbox: inbox)

      expect(record).to be_valid
    end
  end

  describe 'associations' do
    it 'exposes the linked inbox' do
      board = create(:kanban_board)
      inbox = create(:inbox, account: board.account)
      create(:kanban_board_inbox, account: board.account, kanban_board: board, inbox: inbox)

      expect(board.kanban_board_inboxes.count).to eq(1)
      expect(board.allowed_inboxes).to contain_exactly(inbox)
    end
  end
end
