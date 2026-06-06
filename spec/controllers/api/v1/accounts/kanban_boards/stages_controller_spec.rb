require 'rails_helper'

RSpec.describe 'Kanban Stages API', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:kanban_board) { create(:kanban_board, account: account) }

  describe 'POST /api/v1/accounts/{account.id}/kanban_boards/{kanban_board.id}/stages' do
    let(:payload) { { stage: { name: 'Proposal', position: 1, color: 'teal' } } }

    it 'creates a stage for administrators' do
      expect do
        post "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/stages",
             headers: administrator.create_new_auth_token,
             params: payload,
             as: :json
      end.to change(KanbanStage, :count).by(1)

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['name']).to eq('Proposal')
      expect(response.parsed_body['color']).to eq('teal')
      expect(response.parsed_body['position']).to eq(1)
    end

    it 'emits kanban.stage.created with a compact payload' do
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      post "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/stages",
           headers: administrator.create_new_auth_token,
           params: payload,
           as: :json

      stage = KanbanStage.last
      expect(response).to have_http_status(:success)
      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
        Events::Types::KANBAN_STAGE_CREATED,
        anything,
        { account_id: account.id, board_id: kanban_board.id, stage_id: stage.id }
      )
    end

    it 'does not emit kanban.stage.created when create validation fails' do
      create(:kanban_stage, account: account, kanban_board: kanban_board, name: 'Proposal')
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      post "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/stages",
           headers: administrator.create_new_auth_token,
           params: payload,
           as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(Rails.configuration.dispatcher).not_to have_received(:dispatch).with(
        Events::Types::KANBAN_STAGE_CREATED,
        anything,
        anything
      )
    end

    it 'inserts the new stage at the beginning and shifts existing active stages' do
      first_stage = create(:kanban_stage, account: account, kanban_board: kanban_board, name: 'First', position: 1)
      second_stage = create(:kanban_stage, account: account, kanban_board: kanban_board, name: 'Second', position: 2)

      post "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/stages",
           headers: administrator.create_new_auth_token,
           params: { stage: { name: 'Proposal', position: 99, color: 'teal' } },
           as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['position']).to eq(1)
      expect(first_stage.reload.position).to eq(2)
      expect(second_stage.reload.position).to eq(3)
    end

    it 'does not shift inactive stages or stages from other boards' do
      first_stage = create(:kanban_stage, account: account, kanban_board: kanban_board, name: 'First', position: 1)
      inactive_stage = create(
        :kanban_stage,
        account: account,
        kanban_board: kanban_board,
        name: 'Archived',
        position: 5,
        active: false
      )
      other_board = create(:kanban_board, account: account)
      other_board_stage = create(
        :kanban_stage,
        account: account,
        kanban_board: other_board,
        name: 'Other',
        position: 5
      )

      post "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/stages",
           headers: administrator.create_new_auth_token,
           params: { stage: { name: 'Proposal', position: 99, color: 'teal' } },
           as: :json

      expect(response).to have_http_status(:success)
      expect(first_stage.reload.position).to eq(2)
      expect(inactive_stage.reload.position).to eq(5)
      expect(other_board_stage.reload.position).to eq(5)
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
            params: { stage: { name: 'Won', active: false, color: 'ruby' } },
            as: :json

      expect(response).to have_http_status(:success)
      expect(stage.reload.name).to eq('Won')
      expect(stage.color).to eq('ruby')
      expect(stage).not_to be_active
    end

    it 'emits kanban.stage.updated with a compact payload' do
      stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/stages/#{stage.id}",
            headers: administrator.create_new_auth_token,
            params: { stage: { name: 'Won' } },
            as: :json

      expect(response).to have_http_status(:success)
      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
        Events::Types::KANBAN_STAGE_UPDATED,
        anything,
        { account_id: account.id, board_id: kanban_board.id, stage_id: stage.id }
      )
    end

    it 'does not emit kanban.stage.updated when update validation fails' do
      stage = create(:kanban_stage, account: account, kanban_board: kanban_board, name: 'Open')
      create(:kanban_stage, account: account, kanban_board: kanban_board, name: 'Won')
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/stages/#{stage.id}",
            headers: administrator.create_new_auth_token,
            params: { stage: { name: 'Won' } },
            as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(Rails.configuration.dispatcher).not_to have_received(:dispatch).with(
        Events::Types::KANBAN_STAGE_UPDATED,
        anything,
        anything
      )
    end

    it 'does not deactivate a stage with active manual kanban cards' do
      stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
      create(:kanban_card, account: account, kanban_board: kanban_board, kanban_stage: stage, origin: 'manual')

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/stages/#{stage.id}",
            headers: administrator.create_new_auth_token,
            params: { stage: { active: false } },
            as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['error']).to eq(
        'Kanban stage must be empty before it can be removed. Active cards are still assigned to this stage.'
      )
      expect(stage.reload).to be_active
    end

    it 'does not deactivate a stage with active conversation-origin kanban cards' do
      stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
      conversation = create(:conversation, account: account)
      create(
        :kanban_card,
        :conversation_origin,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: conversation
      )

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/stages/#{stage.id}",
            headers: administrator.create_new_auth_token,
            params: { stage: { active: false } },
            as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['error']).to eq(
        'Kanban stage must be empty before it can be removed. Active cards are still assigned to this stage.'
      )
      expect(stage.reload).to be_active
    end

    it 'deactivates a stage with only inactive kanban cards' do
      stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
      create(:kanban_card, account: account, kanban_board: kanban_board, kanban_stage: stage, active: false)

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/stages/#{stage.id}",
            headers: administrator.create_new_auth_token,
            params: { stage: { active: false } },
            as: :json

      expect(response).to have_http_status(:success)
      expect(stage.reload).not_to be_active
    end

    it 'deactivates an empty stage' do
      stage = create(:kanban_stage, account: account, kanban_board: kanban_board)

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/stages/#{stage.id}",
            headers: administrator.create_new_auth_token,
            params: { stage: { active: false } },
            as: :json

      expect(response).to have_http_status(:success)
      expect(stage.reload).not_to be_active
    end

    it 'keeps active true updates unchanged when active kanban cards exist' do
      stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
      create(:kanban_card, account: account, kanban_board: kanban_board, kanban_stage: stage)

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/stages/#{stage.id}",
            headers: administrator.create_new_auth_token,
            params: { stage: { name: 'Qualified', active: true } },
            as: :json

      expect(response).to have_http_status(:success)
      expect(stage.reload.name).to eq('Qualified')
      expect(stage).to be_active
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

  describe 'PATCH /api/v1/accounts/{account.id}/kanban_boards/{kanban_board.id}/stages/{id}/reorder' do
    it 'moves a stage left within its board' do
      first_stage = create(:kanban_stage, account: account, kanban_board: kanban_board, position: 1)
      second_stage = create(:kanban_stage, account: account, kanban_board: kanban_board, position: 2)

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/stages/#{second_stage.id}/reorder",
            headers: administrator.create_new_auth_token,
            params: { direction: 'left' },
            as: :json

      expect(response).to have_http_status(:success)
      expect(second_stage.reload.position).to eq(1)
      expect(first_stage.reload.position).to eq(2)
    end

    it 'emits kanban.stage.reordered with a compact payload' do
      create(:kanban_stage, account: account, kanban_board: kanban_board, position: 1)
      second_stage = create(:kanban_stage, account: account, kanban_board: kanban_board, position: 2)
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/stages/#{second_stage.id}/reorder",
            headers: administrator.create_new_auth_token,
            params: { direction: 'left' },
            as: :json

      expect(response).to have_http_status(:success)
      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
        Events::Types::KANBAN_STAGE_REORDERED,
        anything,
        { account_id: account.id, board_id: kanban_board.id, stage_id: second_stage.id }
      )
    end

    it 'does not emit kanban.stage.reordered when the stage is not found' do
      other_board = create(:kanban_board, account: account)
      other_stage = create(:kanban_stage, account: account, kanban_board: other_board)
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/stages/#{other_stage.id}/reorder",
            headers: administrator.create_new_auth_token,
            params: { direction: 'left' },
            as: :json

      expect(response).to have_http_status(:not_found)
      expect(Rails.configuration.dispatcher).not_to have_received(:dispatch).with(
        Events::Types::KANBAN_STAGE_REORDERED,
        anything,
        anything
      )
    end

    it 'moves a stage right within its board' do
      first_stage = create(:kanban_stage, account: account, kanban_board: kanban_board, position: 1)
      second_stage = create(:kanban_stage, account: account, kanban_board: kanban_board, position: 2)

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/stages/#{first_stage.id}/reorder",
            headers: administrator.create_new_auth_token,
            params: { direction: 'right' },
            as: :json

      expect(response).to have_http_status(:success)
      expect(first_stage.reload.position).to eq(2)
      expect(second_stage.reload.position).to eq(1)
    end

    it 'normalizes duplicated stage positions before moving' do
      first_stage = create(:kanban_stage, account: account, kanban_board: kanban_board, position: 1)
      second_stage = create(:kanban_stage, account: account, kanban_board: kanban_board, position: 1)
      third_stage = create(:kanban_stage, account: account, kanban_board: kanban_board, position: 1)

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/stages/#{third_stage.id}/reorder",
            headers: administrator.create_new_auth_token,
            params: { direction: 'left' },
            as: :json

      expect(response).to have_http_status(:success)
      expect(first_stage.reload.position).to eq(1)
      expect(third_stage.reload.position).to eq(2)
      expect(second_stage.reload.position).to eq(3)
    end

    it 'does not reorder a stage from another board' do
      other_board = create(:kanban_board, account: account)
      other_stage = create(:kanban_stage, account: account, kanban_board: other_board)

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/stages/#{other_stage.id}/reorder",
            headers: administrator.create_new_auth_token,
            params: { direction: 'left' },
            as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'reorders a stage by explicit position' do
      first_stage = create(:kanban_stage, account: account, kanban_board: kanban_board, position: 1)
      second_stage = create(:kanban_stage, account: account, kanban_board: kanban_board, position: 2)
      third_stage = create(:kanban_stage, account: account, kanban_board: kanban_board, position: 3)

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/stages/#{third_stage.id}/reorder",
            headers: administrator.create_new_auth_token,
            params: { position: 1 },
            as: :json

      expect(response).to have_http_status(:success)
      expect(third_stage.reload.position).to eq(1)
      expect(first_stage.reload.position).to eq(2)
      expect(second_stage.reload.position).to eq(3)
    end

    it 'reorders without changing stage membership' do
      create(:kanban_stage, account: account, kanban_board: kanban_board, position: 1)
      second_stage = create(:kanban_stage, account: account, kanban_board: kanban_board, position: 2)

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/stages/#{second_stage.id}/reorder",
            headers: administrator.create_new_auth_token,
            params: { position: 1 },
            as: :json

      expect(response).to have_http_status(:success)
      expect(kanban_board.kanban_stages.active.count).to eq(2)
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/kanban_boards/{kanban_board.id}/stages/{id}' do
    it 'deactivates a stage through its board' do
      stage = create(:kanban_stage, account: account, kanban_board: kanban_board)

      expect do
        delete "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/stages/#{stage.id}",
               headers: administrator.create_new_auth_token,
               as: :json
      end.not_to change(KanbanStage, :count)

      expect(response).to have_http_status(:no_content)
      expect(stage.reload).not_to be_active
    end

    it 'emits kanban.stage.deleted with a compact payload' do
      stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      delete "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/stages/#{stage.id}",
             headers: administrator.create_new_auth_token,
             as: :json

      expect(response).to have_http_status(:no_content)
      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
        Events::Types::KANBAN_STAGE_DELETED,
        anything,
        { account_id: account.id, board_id: kanban_board.id, stage_id: stage.id }
      )
    end

    it 'does not emit kanban.stage.deleted when delete validation fails' do
      stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
      create(:kanban_card, account: account, kanban_board: kanban_board, kanban_stage: stage)
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      delete "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/stages/#{stage.id}",
             headers: administrator.create_new_auth_token,
             as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(Rails.configuration.dispatcher).not_to have_received(:dispatch).with(
        Events::Types::KANBAN_STAGE_DELETED,
        anything,
        anything
      )
    end

    it 'deactivates a stage with only legacy conversation state' do
      stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
      create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage
      )

      delete "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/stages/#{stage.id}",
             headers: administrator.create_new_auth_token,
             as: :json

      expect(response).to have_http_status(:no_content)
      expect(stage.reload).not_to be_active
    end

    it 'does not deactivate a stage with active kanban cards' do
      stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
      create(:kanban_card, account: account, kanban_board: kanban_board, kanban_stage: stage)

      delete "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/stages/#{stage.id}",
             headers: administrator.create_new_auth_token,
             as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['error']).to eq(
        'Kanban stage must be empty before it can be removed. Active cards are still assigned to this stage.'
      )
      expect(stage.reload).to be_active
    end

    it 'does not deactivate a stage with manual active kanban cards' do
      stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
      create(:kanban_card, account: account, kanban_board: kanban_board, kanban_stage: stage, origin: 'manual')

      delete "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/stages/#{stage.id}",
             headers: administrator.create_new_auth_token,
             as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['error']).to eq(
        'Kanban stage must be empty before it can be removed. Active cards are still assigned to this stage.'
      )
      expect(stage.reload).to be_active
    end

    it 'does not deactivate a stage with conversation-origin active kanban cards' do
      stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
      conversation = create(:conversation, account: account)
      create(
        :kanban_card,
        :conversation_origin,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: conversation
      )

      delete "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/stages/#{stage.id}",
             headers: administrator.create_new_auth_token,
             as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['error']).to eq(
        'Kanban stage must be empty before it can be removed. Active cards are still assigned to this stage.'
      )
      expect(stage.reload).to be_active
    end

    it 'deactivates a stage with only inactive kanban cards' do
      stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
      create(:kanban_card, account: account, kanban_board: kanban_board, kanban_stage: stage, active: false)

      delete "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/stages/#{stage.id}",
             headers: administrator.create_new_auth_token,
             as: :json

      expect(response).to have_http_status(:no_content)
      expect(stage.reload).not_to be_active
    end

    it 'deactivates an empty stage' do
      stage = create(:kanban_stage, account: account, kanban_board: kanban_board)

      delete "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/stages/#{stage.id}",
             headers: administrator.create_new_auth_token,
             as: :json

      expect(response).to have_http_status(:no_content)
      expect(stage.reload).not_to be_active
    end

    it 'deactivates a stage when active kanban cards belong to another stage' do
      stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
      other_stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
      create(:kanban_card, account: account, kanban_board: kanban_board, kanban_stage: other_stage)

      delete "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/stages/#{stage.id}",
             headers: administrator.create_new_auth_token,
             as: :json

      expect(response).to have_http_status(:no_content)
      expect(stage.reload).not_to be_active
    end
  end
end
