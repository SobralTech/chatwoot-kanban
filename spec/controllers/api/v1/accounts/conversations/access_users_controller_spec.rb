require 'rails_helper'

RSpec.describe 'Conversation Access Users API', type: :request do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:access_users_url) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/access_users" }
  let(:eligible_access_users_url) { "#{access_users_url}/eligible" }

  before do
    create(:inbox_member, inbox: conversation.inbox, user: agent)
  end

  describe 'authorization' do
    it 'does not allow a non-admin agent to show access users' do
      get access_users_url, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'does not allow a non-admin agent to update access users' do
      put access_users_url, params: { user_ids: [] }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'does not allow a non-admin agent to list eligible access users' do
      get eligible_access_users_url, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/conversations/<id>/access_users' do
    it 'allows an admin to show selected access users' do
      create(:conversation_access_user, account: account, conversation: conversation, user: agent)

      get access_users_url, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload'].pluck('id')).to contain_exactly(agent.id)
    end

    it 'includes a previously selected agent who lost base access with effective_access false' do
      create(:conversation_access_user, account: account, conversation: conversation, user: agent)
      InboxMember.find_by!(inbox: conversation.inbox, user: agent).destroy!

      get access_users_url, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload']).to include(hash_including('id' => agent.id, 'effective_access' => false))
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/conversations/<id>/access_users/eligible' do
    it 'allows an admin to list eligible agents' do
      get eligible_access_users_url, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload'].pluck('id')).to contain_exactly(agent.id)
    end
  end

  describe 'PUT /api/v1/accounts/{account.id}/conversations/<id>/access_users' do
    let(:eligible_agent) { create(:user, account: account, role: :agent) }

    before do
      create(:inbox_member, inbox: conversation.inbox, user: eligible_agent)
    end

    it 'allows an admin to update selected access users' do
      put access_users_url, params: { user_ids: [eligible_agent.id] }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(conversation.conversation_access_users.pluck(:user_id)).to contain_exactly(eligible_agent.id)
      expect(response.parsed_body['payload'].pluck('id')).to contain_exactly(eligible_agent.id)
    end

    it 'rejects and does not persist an admin user id manually included in user_ids' do
      put access_users_url, params: { user_ids: [admin.id] }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(conversation.conversation_access_users.pluck(:user_id)).to be_empty
    end

    it 'rejects and does not persist a user from another account' do
      other_account_agent = create(:user, account: create(:account), role: :agent)

      put access_users_url, params: { user_ids: [other_account_agent.id] }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(conversation.conversation_access_users.pluck(:user_id)).to be_empty
    end

    it 'rejects and does not persist an account user without agent role' do
      account_admin = create(:user, account: account, role: :administrator)

      put access_users_url, params: { user_ids: [account_admin.id] }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(conversation.conversation_access_users.pluck(:user_id)).to be_empty
    end

    it 'rejects and does not persist an agent without base access as a new eligible user' do
      agent_without_base_access = create(:user, account: account, role: :agent)

      put access_users_url, params: { user_ids: [agent_without_base_access.id] }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(conversation.conversation_access_users.pluck(:user_id)).to be_empty
    end

    it 'allows a revoked agent to be removed' do
      create(:conversation_access_user, account: account, conversation: conversation, user: eligible_agent)
      InboxMember.find_by!(inbox: conversation.inbox, user: eligible_agent).destroy!

      put access_users_url, params: { user_ids: [] }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(conversation.conversation_access_users.pluck(:user_id)).to be_empty
    end

    it 'keeps a previously selected revoked agent when still submitted' do
      create(:conversation_access_user, account: account, conversation: conversation, user: eligible_agent)
      InboxMember.find_by!(inbox: conversation.inbox, user: eligible_agent).destroy!

      put access_users_url, params: { user_ids: [eligible_agent.id] }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(conversation.conversation_access_users.pluck(:user_id)).to contain_exactly(eligible_agent.id)
      expect(response.parsed_body['payload']).to include(hash_including('id' => eligible_agent.id, 'effective_access' => false))
    end

    it 'removes restriction and returns no selected access users when user_ids is empty' do
      create(:conversation_access_user, account: account, conversation: conversation, user: eligible_agent)

      put access_users_url, params: { user_ids: [] }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(conversation.conversation_access_users.pluck(:user_id)).to be_empty
      expect(response.parsed_body['payload']).to be_empty
    end

    it 'dispatches access_revoked only for users who lost access' do
      conversation.update!(access_mode: :selected_agents)
      create(:conversation_access_user, account: account, conversation: conversation, user: agent)
      create(:conversation_access_user, account: account, conversation: conversation, user: eligible_agent)

      allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original
      expect(Rails.configuration.dispatcher).to receive(:dispatch).with(
        'conversation.access_revoked',
        anything,
        conversation: conversation,
        tokens: contain_exactly(agent.pubsub_token)
      )

      put access_users_url, params: { user_ids: [eligible_agent.id] }, headers: admin.create_new_auth_token, as: :json
    end

    it 'does not dispatch access_revoked to users who remain authorized' do
      conversation.update!(access_mode: :selected_agents)
      create(:conversation_access_user, account: account, conversation: conversation, user: eligible_agent)

      allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original
      expect(Rails.configuration.dispatcher).not_to receive(:dispatch).with('conversation.access_revoked', anything, anything)

      put access_users_url, params: { user_ids: [eligible_agent.id] }, headers: admin.create_new_auth_token, as: :json
    end

    it 'does not calculate revoked users from submitted params only' do
      conversation.update!(access_mode: :selected_agents)
      create(:conversation_access_user, account: account, conversation: conversation, user: eligible_agent)
      create(:conversation_access_user, account: account, conversation: conversation, user: agent)

      allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original
      expect(Rails.configuration.dispatcher).not_to receive(:dispatch).with('conversation.access_revoked', anything, anything)

      put access_users_url, params: { user_ids: [] }, headers: admin.create_new_auth_token, as: :json
    end
  end
end
