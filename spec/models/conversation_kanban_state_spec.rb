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
end
