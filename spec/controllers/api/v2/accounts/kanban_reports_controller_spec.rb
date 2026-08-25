require 'rails_helper'

RSpec.describe 'Kanban reports API', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:board) { create(:kanban_board, account: account) }
  let!(:won_stage) { create(:kanban_stage, account: account, kanban_board: board, position: 2, name: 'Won') }
  let!(:lost_stage) { create(:kanban_stage, account: account, kanban_board: board, position: 3, name: 'Lost') }
  let(:since) { Time.zone.parse('2026-08-01 00:00:00 UTC').to_i }
  let(:until_time) { Time.zone.parse('2026-08-08 00:00:00 UTC').to_i }
  let(:report_params) do
    {
      kanban_board_id: board.id,
      since: since,
      until: until_time,
      group_by: 'day',
      timezone_offset: 0
    }
  end

  before do
    board.update!(won_stage_id: won_stage.id, lost_stage_id: lost_stage.id)
  end

  describe 'GET /api/v2/accounts/:account_id/kanban_reports' do
    it 'requires authentication' do
      get "/api/v2/accounts/#{account.id}/kanban_reports", params: report_params

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns the aggregated funnel for an administrator' do
      card = create(:kanban_card, account: account, kanban_board: board, kanban_stage: won_stage, inbox: inbox)
      create(:kanban_card_event, account: account, kanban_card: card, kanban_board: board, event_type: 'won',
                                 metadata: { stage_id: won_stage.id }, created_at: Time.zone.at(since + 86_400))

      get "/api/v2/accounts/#{account.id}/kanban_reports",
          params: report_params,
          headers: administrator.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include(
        'board' => include('id' => board.id),
        'summary' => include('won' => include('count' => 1)),
        'conversion' => be_an(Array),
        'won_lost' => include('series' => be_an(Array))
      )
    end

    it 'allows an agent to see only a board in their policy scope' do
      create(:inbox_member, user: agent, inbox: inbox)
      board.update!(visibility_mode: 'selected_agents')
      create(:kanban_board_member, account: account, kanban_board: board, user: agent)

      get "/api/v2/accounts/#{account.id}/kanban_reports",
          params: report_params,
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['board']['id']).to eq(board.id)
    end

    it 'returns no selected data when the agent cannot see any board' do
      board.update!(visibility_mode: 'selected_agents')

      get "/api/v2/accounts/#{account.id}/kanban_reports",
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include('selected_board_id' => nil, 'data' => nil)
      expect(response.parsed_body['boards']).to be_empty
    end

    it 'returns not found for a board outside the account scope' do
      other_board = create(:kanban_board)

      get "/api/v2/accounts/#{account.id}/kanban_reports",
          params: report_params.merge(kanban_board_id: other_board.id),
          headers: administrator.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET /api/v2/accounts/:account_id/kanban_reports/conversion' do
    it 'returns conversion CSV' do
      get "/api/v2/accounts/#{account.id}/kanban_reports/conversion.csv",
          params: report_params,
          headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(response.media_type).to eq('text/csv')
      expect(response.body).to include('stage_id,stage_name,count,conversion_rate')
    end
  end
end
