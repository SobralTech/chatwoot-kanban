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
      expect(response.parsed_body.first['auto_create_cards_from_conversations']).to be(false)
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
      expect(response.parsed_body['auto_create_cards_from_conversations']).to be(false)
    end

    it 'accepts automatic card creation setting' do
      post "/api/v1/accounts/#{account.id}/kanban_boards",
           headers: administrator.create_new_auth_token,
           params: { kanban_board: payload[:kanban_board].merge(auto_create_cards_from_conversations: true) },
           as: :json

      expect(response).to have_http_status(:success)
      expect(KanbanBoard.last.auto_create_cards_from_conversations).to be(true)
      expect(response.parsed_body['auto_create_cards_from_conversations']).to be(true)
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

    it 'updates automatic card creation from false to true' do
      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}",
            headers: administrator.create_new_auth_token,
            params: { kanban_board: { auto_create_cards_from_conversations: true } },
            as: :json

      expect(response).to have_http_status(:success)
      expect(kanban_board.reload.auto_create_cards_from_conversations).to be(true)
      expect(response.parsed_body['auto_create_cards_from_conversations']).to be(true)
    end

    it 'updates automatic card creation from true to false' do
      kanban_board.update!(auto_create_cards_from_conversations: true)

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}",
            headers: administrator.create_new_auth_token,
            params: { kanban_board: { auto_create_cards_from_conversations: false } },
            as: :json

      expect(response).to have_http_status(:success)
      expect(kanban_board.reload.auto_create_cards_from_conversations).to be(false)
      expect(response.parsed_body['auto_create_cards_from_conversations']).to be(false)
    end

    it 'accepts an active default stage from the same board' do
      stage = create(:kanban_stage, account: account, kanban_board: kanban_board)

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}",
            headers: administrator.create_new_auth_token,
            params: { kanban_board: { default_stage_id: stage.id } },
            as: :json

      expect(response).to have_http_status(:success)
      expect(kanban_board.reload.default_stage_id).to eq(stage.id)
    end

    it 'rejects a default stage from another board' do
      other_board = create(:kanban_board, account: account)
      stage = create(:kanban_stage, account: account, kanban_board: other_board)

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}",
            headers: administrator.create_new_auth_token,
            params: { kanban_board: { default_stage_id: stage.id } },
            as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(kanban_board.reload.default_stage_id).to be_nil
    end

    it 'rejects an inactive default stage' do
      stage = create(:kanban_stage, account: account, kanban_board: kanban_board, active: false)

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}",
            headers: administrator.create_new_auth_token,
            params: { kanban_board: { default_stage_id: stage.id } },
            as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(kanban_board.reload.default_stage_id).to be_nil
    end

    it 'returns the default stage id' do
      stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
      kanban_board.update!(default_stage: stage)

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}",
            headers: administrator.create_new_auth_token,
            params: { kanban_board: { name: 'Updated Sales' } },
            as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['default_stage_id']).to eq(stage.id)
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
