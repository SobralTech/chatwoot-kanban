require 'rails_helper'

RSpec.describe KanbanBoardMember do
  describe 'validations' do
    it 'prevents duplicate users inside a board' do
      board = create(:kanban_board)
      user = create(:user, account: board.account)
      create(:kanban_board_member, account: board.account, kanban_board: board, user: user)

      member = build(:kanban_board_member, account: board.account, kanban_board: board, user: user)

      expect(member).not_to be_valid
      expect(member.errors[:user_id]).to be_present
    end

    it 'rejects a member with an account different from the board account' do
      board = create(:kanban_board)
      other_account = create(:account)
      user = create(:user, account: other_account)

      member = build(:kanban_board_member, account: other_account, kanban_board: board, user: user)

      expect(member).not_to be_valid
      expect(member.errors[:account_id]).to be_present
    end

    it 'rejects a user without an AccountUser in the member account' do
      board = create(:kanban_board)
      user = create(:user)

      member = build(:kanban_board_member, account: board.account, kanban_board: board, user: user)

      expect(member).not_to be_valid
      expect(member.errors[:user_id]).to be_present
    end

    it 'accepts a user that belongs to the member account' do
      board = create(:kanban_board)
      user = create(:user, account: board.account)

      member = build(:kanban_board_member, account: board.account, kanban_board: board, user: user)

      expect(member).to be_valid
    end
  end
end
