require 'rails_helper'

RSpec.describe ConversationKanbanState do
  describe 'validations' do
    it 'allows a conversation once per board' do
      board = create(:kanban_board)
      stage = create(:kanban_stage, account: board.account, kanban_board: board)
      conversation = create(:conversation, account: board.account)
      create(
        :conversation_kanban_state,
        account: board.account,
        kanban_board: board,
        kanban_stage: stage,
        conversation: conversation
      )

      state = build(
        :conversation_kanban_state,
        account: board.account,
        kanban_board: board,
        kanban_stage: stage,
        conversation: conversation
      )

      expect(state).not_to be_valid
      expect(state.errors[:conversation_id]).to be_present
    end

    it 'validates board, stage, and conversation belong to the same account' do
      board = create(:kanban_board)
      other_conversation = create(:conversation)
      stage = create(:kanban_stage, account: board.account, kanban_board: board)

      state = build(
        :conversation_kanban_state,
        account: board.account,
        kanban_board: board,
        kanban_stage: stage,
        conversation: other_conversation
      )

      expect(state).not_to be_valid
      expect(state.errors[:conversation]).to be_present
    end
  end

  describe '.normalize_positions_for_stage!' do
    it 'normalizes cards inside the stage by position, creation time, and id' do
      board = create(:kanban_board)
      stage = create(:kanban_stage, account: board.account, kanban_board: board)
      later_state = create(
        :conversation_kanban_state,
        account: board.account,
        kanban_board: board,
        kanban_stage: stage,
        position: 2
      )
      first_duplicate = create(
        :conversation_kanban_state,
        account: board.account,
        kanban_board: board,
        kanban_stage: stage,
        position: 1
      )
      second_duplicate = create(
        :conversation_kanban_state,
        account: board.account,
        kanban_board: board,
        kanban_stage: stage,
        position: 1
      )

      described_class.normalize_positions_for_stage!(kanban_board: board, kanban_stage: stage)

      expect(first_duplicate.reload.position).to eq(1)
      expect(second_duplicate.reload.position).to eq(2)
      expect(later_state.reload.position).to eq(3)
    end

    it 'does not normalize cards from another stage or board' do
      board = create(:kanban_board)
      stage = create(:kanban_stage, account: board.account, kanban_board: board)
      other_stage = create(:kanban_stage, account: board.account, kanban_board: board)
      other_board = create(:kanban_board, account: board.account)
      other_board_stage = create(:kanban_stage, account: board.account, kanban_board: other_board)
      state = create(:conversation_kanban_state, account: board.account, kanban_board: board, kanban_stage: stage, position: 10)
      other_stage_state = create(
        :conversation_kanban_state,
        account: board.account,
        kanban_board: board,
        kanban_stage: other_stage,
        position: 10
      )
      other_board_state = create(
        :conversation_kanban_state,
        account: board.account,
        kanban_board: other_board,
        kanban_stage: other_board_stage,
        position: 10
      )

      described_class.normalize_positions_for_stage!(kanban_board: board, kanban_stage: stage)

      expect(state.reload.position).to eq(1)
      expect(other_stage_state.reload.position).to eq(10)
      expect(other_board_state.reload.position).to eq(10)
    end
  end
end
