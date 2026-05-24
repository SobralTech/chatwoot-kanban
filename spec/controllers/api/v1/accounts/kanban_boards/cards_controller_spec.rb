require 'rails_helper'

RSpec.describe 'Kanban Cards API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:kanban_board) { create(:kanban_board, account: account) }
  let(:stage) { create(:kanban_stage, account: account, kanban_board: kanban_board) }
  let(:conversation) { create(:conversation, account: account) }

  before do
    create(:inbox_member, user: agent, inbox: conversation.inbox)
  end

  describe 'POST /api/v1/accounts/{account.id}/kanban_boards/{kanban_board.id}/cards' do
    it 'creates a card for a conversation the agent can access' do
      expect do
        post "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards",
             headers: agent.create_new_auth_token,
             params: { card: { conversation_id: conversation.display_id, kanban_stage_id: stage.id, position: 2 } },
             as: :json
      end.to change(ConversationKanbanState, :count).by(1)

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['conversation_id']).to eq(conversation.display_id)
      expect(response.parsed_body['position']).to eq(2)
      expect(ConversationKanbanState.last.moved_by).to eq(agent)
      expect(ConversationKanbanState.last.moved_at).to be_present
    end

    it 'does not create a card for a conversation the agent cannot access' do
      hidden_conversation = create(:conversation, account: account)

      expect do
        post "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards",
             headers: agent.create_new_auth_token,
             params: { card: { conversation_id: hidden_conversation.display_id, kanban_stage_id: stage.id } },
             as: :json
      end.not_to change(ConversationKanbanState, :count)

      expect(response).to have_http_status(:unauthorized)
    end

    it 'does not create a card on a stage from another board' do
      other_board = create(:kanban_board, account: account)
      other_stage = create(:kanban_stage, account: account, kanban_board: other_board)

      post "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards",
           headers: agent.create_new_auth_token,
           params: { card: { conversation_id: conversation.display_id, kanban_stage_id: other_stage.id } },
           as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/kanban_boards/{kanban_board.id}/cards/{conversation_id}' do
    it 'moves an existing card' do
      next_stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
      card = create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: conversation,
        position: 1
      )

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/#{conversation.display_id}",
            headers: agent.create_new_auth_token,
            params: { card: { kanban_stage_id: next_stage.id, position: 3 } },
            as: :json

      expect(response).to have_http_status(:success)
      expect(card.reload.kanban_stage).to eq(next_stage)
      expect(card.position).to eq(3)
      expect(card.moved_by).to eq(agent)
      expect(card.moved_at).to be_present
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/kanban_boards/{kanban_board.id}/cards/{conversation_id}/reorder' do
    it 'moves a card up within the same stage' do
      next_conversation = create(:conversation, account: account)
      create(:inbox_member, user: agent, inbox: next_conversation.inbox)
      first_card = create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: conversation,
        position: 1
      )
      second_card = create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: next_conversation,
        position: 2
      )

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/#{next_conversation.display_id}/reorder",
            headers: agent.create_new_auth_token,
            params: { direction: 'up' },
            as: :json

      expect(response).to have_http_status(:success)
      expect(second_card.reload.position).to eq(1)
      expect(first_card.reload.position).to eq(2)
    end

    it 'moves a card down within the same stage' do
      next_conversation = create(:conversation, account: account)
      create(:inbox_member, user: agent, inbox: next_conversation.inbox)
      first_card = create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: conversation,
        position: 1
      )
      second_card = create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: next_conversation,
        position: 2
      )

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/#{conversation.display_id}/reorder",
            headers: agent.create_new_auth_token,
            params: { direction: 'down' },
            as: :json

      expect(response).to have_http_status(:success)
      expect(first_card.reload.position).to eq(2)
      expect(second_card.reload.position).to eq(1)
    end

    it 'does not reorder cards from another stage' do
      next_conversation = create(:conversation, account: account)
      third_conversation = create(:conversation, account: account)
      create(:inbox_member, user: agent, inbox: next_conversation.inbox)
      create(:inbox_member, user: agent, inbox: third_conversation.inbox)
      other_stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
      first_card = create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: conversation,
        position: 1
      )
      other_stage_card = create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: other_stage,
        conversation: next_conversation,
        position: 2
      )
      third_card = create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: third_conversation,
        position: 3
      )

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/#{conversation.display_id}/reorder",
            headers: agent.create_new_auth_token,
            params: { direction: 'down' },
            as: :json

      expect(response).to have_http_status(:success)
      expect(first_card.reload.position).to eq(3)
      expect(third_card.reload.position).to eq(1)
      expect(other_stage_card.reload.position).to eq(2)
    end

    it 'does not reorder a card from another board' do
      other_board = create(:kanban_board, account: account)
      other_stage = create(:kanban_stage, account: account, kanban_board: other_board)
      create(
        :conversation_kanban_state,
        account: account,
        kanban_board: other_board,
        kanban_stage: other_stage,
        conversation: conversation,
        position: 1
      )

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/#{conversation.display_id}/reorder",
            headers: agent.create_new_auth_token,
            params: { direction: 'down' },
            as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/kanban_boards/{kanban_board.id}/cards/{conversation_id}' do
    it 'removes a card from the board' do
      create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: conversation
      )

      expect do
        delete "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/#{conversation.display_id}",
               headers: agent.create_new_auth_token,
               as: :json
      end.to change(ConversationKanbanState, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end
  end
end
