require 'rails_helper'

RSpec.describe 'Kanban card bulk actions API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:kanban_board) { create(:kanban_board, account: account) }
  let(:regular_stage) { create(:kanban_stage, account: account, kanban_board: kanban_board) }
  let(:inbox) { create(:inbox, account: account) }
  let(:url) { "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/bulk_actions" }

  describe 'POST /api/v1/accounts/{account.id}/kanban_boards/{board.id}/cards/bulk_actions' do
    it 'returns unauthorized for an unauthenticated request' do
      post url, params: { operation: 'priority', card_ids: [1], payload: { priority: 'high' } }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'applies the requested operation to every card' do
      cards = Array.new(2) { create_card }

      post url,
           params: { operation: 'priority', card_ids: cards.map(&:id), payload: { priority: 'high' } },
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to eq('succeeded' => cards.map(&:id), 'failed' => [])
      expect(cards.map { |card| card.reload.priority }).to all(eq('high'))
    end

    it 'moves cards to the requested stage' do
      card = create_card
      target_stage = create(:kanban_stage, account: account, kanban_board: kanban_board, name: 'Negotiation')

      post url,
           params: { operation: 'move', card_ids: [card.id], payload: { kanban_stage_id: target_stage.id } },
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(card.reload.kanban_stage_id).to eq(target_stage.id)
    end

    it 'rejects an unsupported operation' do
      post url,
           params: { operation: 'explode', card_ids: [1] },
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['error']).to eq('bulk_action_not_supported')
    end

    it 'rejects more cards than the service allows' do
      post url,
           params: { operation: 'priority', card_ids: (1..(described_class_max_cards + 1)).to_a, payload: { priority: 'high' } },
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['error']).to eq('bulk_action_limit_exceeded')
    end

    it 'rejects losing cards when the board requires a reason and none was given' do
      kanban_board.update!(lost_stage_id: create(:kanban_stage, account: account, kanban_board: kanban_board, name: 'Lost').id,
                           lost_reason_required: true)

      post url,
           params: { operation: 'lose', card_ids: [create_card.id] },
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['error']).to eq('lost_reason_required')
    end
  end

  def create_card
    create(
      :kanban_card,
      account: account,
      kanban_board: kanban_board,
      kanban_stage: regular_stage,
      contact: create(:contact, account: account),
      inbox: inbox,
      subject: 'Opportunity',
      position: 1
    )
  end

  def described_class_max_cards
    KanbanCards::BulkActionRequest::MAX_CARDS
  end
end
