require 'rails_helper'

RSpec.describe 'Kanban Stages API', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:kanban_board) { create(:kanban_board, account: account) }

  describe 'POST /api/v1/accounts/{account.id}/kanban_boards/{kanban_board.id}/stages' do
    let(:payload) { { stage: { name: 'Proposal', position: 1 } } }

    it 'creates a stage for administrators' do
      expect do
        post "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/stages",
             headers: administrator.create_new_auth_token,
             params: payload,
             as: :json
      end.to change(KanbanStage, :count).by(1)

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['name']).to eq('Proposal')
    end

    it 'returns unauthorized for agents' do
      post "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/stages",
           headers: agent.create_new_auth_token,
           params: payload,
           as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/kanban_boards/{kanban_board.id}/stages/{id}' do
    it 'updates a stage through its board' do
      stage = create(:kanban_stage, account: account, kanban_board: kanban_board)

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/stages/#{stage.id}",
            headers: administrator.create_new_auth_token,
            params: { stage: { name: 'Won', active: false } },
            as: :json

      expect(response).to have_http_status(:success)
      expect(stage.reload.name).to eq('Won')
      expect(stage).not_to be_active
    end

    it 'does not update a stage from another board' do
      other_board = create(:kanban_board, account: account)
      other_stage = create(:kanban_stage, account: account, kanban_board: other_board)

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/stages/#{other_stage.id}",
            headers: administrator.create_new_auth_token,
            params: { stage: { name: 'Won' } },
            as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/kanban_boards/{kanban_board.id}/stages/{id}' do
    it 'deletes a stage through its board' do
      stage = create(:kanban_stage, account: account, kanban_board: kanban_board)

      expect do
        delete "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/stages/#{stage.id}",
               headers: administrator.create_new_auth_token,
               as: :json
      end.to change(KanbanStage, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end
  end
end
