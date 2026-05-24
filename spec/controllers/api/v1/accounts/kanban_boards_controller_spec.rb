require 'rails_helper'

RSpec.describe 'Kanban Boards API', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let!(:kanban_board) { create(:kanban_board, account: account, name: 'Sales') }

  describe 'GET /api/v1/accounts/{account.id}/kanban_boards' do
    it 'returns unauthorized for unauthenticated users' do
      get "/api/v1/accounts/#{account.id}/kanban_boards"

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns boards for agents' do
      get "/api/v1/accounts/#{account.id}/kanban_boards",
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body.first['name']).to eq('Sales')
    end

    it 'does not return inactive boards' do
      create(:kanban_board, account: account, active: false)

      get "/api/v1/accounts/#{account.id}/kanban_boards",
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body.pluck('active')).to all be(true)
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/kanban_boards/{id}' do
    it 'returns board stages and cards' do
      stage = create(:kanban_stage, account: account, kanban_board: kanban_board, name: 'New')
      conversation = create(:conversation, account: account)
      create(:inbox_member, user: agent, inbox: conversation.inbox)
      create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: conversation
      )

      get "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}",
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['stages'].first['name']).to eq('New')
      expect(response.parsed_body['stages'].first['cards'].first['conversation_id']).to eq(conversation.display_id)
    end

    it 'does not return boards from another account' do
      other_board = create(:kanban_board)

      get "/api/v1/accounts/#{account.id}/kanban_boards/#{other_board.id}",
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'returns stages and cards ordered by position' do
      later_stage = create(:kanban_stage, account: account, kanban_board: kanban_board, name: 'Later', position: 2)
      earlier_stage = create(:kanban_stage, account: account, kanban_board: kanban_board, name: 'Earlier', position: 1)
      later_conversation = create(:conversation, account: account)
      earlier_conversation = create(:conversation, account: account)
      create(:inbox_member, user: agent, inbox: later_conversation.inbox)
      create(:inbox_member, user: agent, inbox: earlier_conversation.inbox)
      create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: earlier_stage,
        conversation: later_conversation,
        position: 2
      )
      create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: earlier_stage,
        conversation: earlier_conversation,
        position: 1
      )

      get "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}",
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['stages'].pluck('id')).to eq([earlier_stage.id, later_stage.id])
      expect(response.parsed_body['stages'].first['cards'].pluck('conversation_id')).to eq(
        [earlier_conversation.display_id, later_conversation.display_id]
      )
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/kanban_boards' do
    let(:payload) { { kanban_board: { name: 'Support', description: 'Support funnel', position: 1 } } }

    it 'creates a board for administrators' do
      expect do
        post "/api/v1/accounts/#{account.id}/kanban_boards",
             headers: administrator.create_new_auth_token,
             params: payload,
             as: :json
      end.to change(KanbanBoard, :count).by(1)

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['name']).to eq('Support')
    end

    it 'returns unauthorized for agents' do
      post "/api/v1/accounts/#{account.id}/kanban_boards",
           headers: agent.create_new_auth_token,
           params: payload,
           as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/kanban_boards/{id}' do
    it 'updates a board for administrators' do
      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}",
            headers: administrator.create_new_auth_token,
            params: { kanban_board: { name: 'Updated Sales', active: false } },
            as: :json

      expect(response).to have_http_status(:success)
      expect(kanban_board.reload.name).to eq('Updated Sales')
      expect(kanban_board).not_to be_active
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/kanban_boards/{id}' do
    it 'deactivates a board for administrators' do
      expect do
        delete "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}",
               headers: administrator.create_new_auth_token,
               as: :json
      end.not_to change(KanbanBoard, :count)

      expect(response).to have_http_status(:no_content)
      expect(kanban_board.reload).not_to be_active
    end
  end
end
