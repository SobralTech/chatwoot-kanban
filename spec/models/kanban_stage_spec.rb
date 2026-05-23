require 'rails_helper'

RSpec.describe KanbanStage do
  describe 'validations' do
    it 'validates name uniqueness inside a board' do
      board = create(:kanban_board)
      create(:kanban_stage, account: board.account, kanban_board: board, name: 'New')

      stage = build(:kanban_stage, account: board.account, kanban_board: board, name: 'New')

      expect(stage).not_to be_valid
      expect(stage.errors[:name]).to be_present
    end

    it 'validates the board belongs to the same account' do
      board = create(:kanban_board)
      other_account = create(:account)

      stage = build(:kanban_stage, account: other_account, kanban_board: board)

      expect(stage).not_to be_valid
      expect(stage.errors[:account_id]).to be_present
    end
  end
end
