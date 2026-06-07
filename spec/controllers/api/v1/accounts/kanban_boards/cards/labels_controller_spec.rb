require 'rails_helper'

RSpec.describe 'Kanban Card Labels API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:kanban_board) { create(:kanban_board, account: account) }
  let(:stage) { create(:kanban_stage, account: account, kanban_board: kanban_board) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:card) { create(:kanban_card, account: account, kanban_board: kanban_board, kanban_stage: stage, inbox: inbox, contact: contact) }
  let(:hot_label) { create(:label, account: account, title: 'hot', color: '#ff0000', description: nil) }
  let(:enterprise_label) { create(:label, account: account, title: 'enterprise', color: '#00ff00', description: 'Enterprise deal') }

  before do
    create(:inbox_member, user: agent, inbox: inbox)
  end

  describe 'GET /api/v1/accounts/{account.id}/kanban_boards/{kanban_board.id}/cards/by_id/{card.id}/labels' do
    it 'returns assigned card labels' do
      card.update_labels([hot_label.title])

      get labels_url(card), headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload'].pluck('title')).to contain_exactly('hot')
    end

    it 'returns label metadata' do
      card.update_labels([hot_label.title])

      get labels_url(card), headers: agent.create_new_auth_token, as: :json

      expect(response.parsed_body['payload']).to contain_exactly(
        hash_including('id' => hot_label.id, 'title' => 'hot', 'color' => '#ff0000', 'description' => nil)
      )
    end

    it 'rejects unauthorized card access' do
      agent.inbox_members.destroy_all

      get labels_url(card), headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejects a card from another board' do
      other_board = create(:kanban_board, account: account)

      get labels_url(card, kanban_board: other_board), headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'rejects labels access when the board is inactive' do
      kanban_board.update!(active: false)

      get labels_url(card), headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'rejects labels access when the card stage is inactive' do
      stage.update!(active: false)

      get labels_url(card), headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'PUT /api/v1/accounts/{account.id}/kanban_boards/{kanban_board.id}/cards/by_id/{card.id}/labels' do
    it 'replaces the complete label set' do
      card.update_labels([hot_label.title])
      enterprise_label

      put labels_url(card), params: { labels: ['enterprise'] }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(card.reload.label_list).to contain_exactly('enterprise')
      expect(response.parsed_body['payload'].pluck('title')).to contain_exactly('enterprise')
    end

    it 'supports empty array to clear labels' do
      card.update_labels([hot_label.title])

      put labels_url(card), params: { labels: [] }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(card.reload.label_list).to be_empty
      expect(response.parsed_body['payload']).to be_empty
    end

    it 'deduplicates titles' do
      hot_label

      put labels_url(card), params: { labels: %w[hot hot] }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(card.reload.label_list).to contain_exactly('hot')
    end

    it 'rejects unknown label title with 422' do
      hot_label

      put labels_url(card), params: { labels: %w[hot missing] }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(card.reload.label_list).to be_empty
    end

    it 'keeps labels account-scoped' do
      create(:label, account: create(:account), title: 'external')

      put labels_url(card), params: { labels: ['external'] }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(card.reload.label_list).to be_empty
    end

    it 'updates manual cards' do
      hot_label

      put labels_url(card), params: { labels: ['hot'] }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(card.reload.label_list).to contain_exactly('hot')
    end

    it 'updates conversation-origin cards' do
      conversation = create(:conversation, account: account, inbox: inbox, contact: contact)
      conversation_card = create(
        :kanban_card,
        :conversation_origin,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: conversation
      )
      hot_label

      put labels_url(conversation_card), params: { labels: ['hot'] }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(conversation_card.reload.label_list).to contain_exactly('hot')
    end

    it 'rejects label updates when the board is inactive' do
      hot_label
      kanban_board.update!(active: false)

      put labels_url(card), params: { labels: ['hot'] }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
      expect(card.reload.label_list).to be_empty
    end

    it 'rejects label updates when the card stage is inactive' do
      hot_label
      stage.update!(active: false)

      put labels_url(card), params: { labels: ['hot'] }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
      expect(card.reload.label_list).to be_empty
    end

    it 'rejects label index when board is not visible to agent' do
      kanban_board.update!(visibility_mode: 'selected_agents')

      get labels_url(card), headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'rejects label update when board is not visible to agent' do
      kanban_board.update!(visibility_mode: 'selected_agents')

      put labels_url(card), params: { labels: ['hot'] }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'allows admin label operations on selected_agents board without membership' do
      kanban_board.update!(visibility_mode: 'selected_agents')
      card.update_labels([hot_label.title])

      get labels_url(card), headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
    end
  end

  def labels_url(target_card, kanban_board: self.kanban_board)
    "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/by_id/#{target_card.id}/labels"
  end
end
