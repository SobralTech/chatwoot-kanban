# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Enterprise Reports API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }

  # Create a custom role with report_manage permission
  let!(:custom_role) { create(:custom_role, account: account, permissions: ['report_manage']) }
  let!(:agent_with_role) { create(:user, account: account, role: :agent) }
  let(:agent_with_role_account_user) do
    agent_with_role.account_users.find_by!(account: account).tap { |account_user| account_user.update!(custom_role: custom_role) }
  end

  let(:default_timezone) { 'UTC' }
  let(:start_of_today) { Time.current.in_time_zone(default_timezone).beginning_of_day.to_i }
  let(:end_of_today) { Time.current.in_time_zone(default_timezone).end_of_day.to_i }
  let(:params) { { timezone_offset: Time.zone.utc_offset } }

  before do
    agent_with_role_account_user
  end

  describe 'GET /api/v2/accounts/:account_id/reports' do
    context 'when it is an authenticated user' do
      let(:params) do
        super().merge(
          metric: 'conversations_count',
          type: :account,
          since: start_of_today.to_s,
          until: end_of_today.to_s
        )
      end

      it 'returns success for agents with report_manage permission' do
        get "/api/v2/accounts/#{account.id}/reports",
            params: params,
            headers: agent_with_role.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'GET /api/v2/accounts/:account_id/reports/summary' do
    context 'when it is an authenticated user' do
      let(:params) do
        super().merge(
          type: :account,
          since: start_of_today.to_s,
          until: end_of_today.to_s
        )
      end

      it 'returns success for agents with report_manage permission' do
        get "/api/v2/accounts/#{account.id}/reports/summary",
            params: params,
            headers: agent_with_role.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'GET /api/v2/accounts/:account_id/live_reports/conversation_metrics' do
    context 'when it is an authenticated report_manage user' do
      let(:inbox) { create(:inbox, account: account) }
      let(:allowed_conversation) { create(:conversation, account: account, inbox: inbox, status: 'open') }
      let(:restricted_conversation) { create(:conversation, account: account, inbox: inbox, status: 'open') }
      let(:authorized_agent) { create(:user, account: account, role: :agent) }

      before do
        create(:inbox_member, inbox: inbox, user: agent_with_role)
        create(:inbox_member, inbox: inbox, user: authorized_agent)
        create(:conversation_access_user, account: account, conversation: restricted_conversation, user: authorized_agent)
        allowed_conversation
      end

      it 'excludes conversations restricted away from the report_manage user' do
        service = Conversations::PermissionFilterService.new(account.conversations, agent_with_role, account)
        visible_conversations = service.access_list_restricted(account.conversations)
        expect(visible_conversations.open.count).to eq(1)

        get "/api/v2/accounts/#{account.id}/live_reports/conversation_metrics",
            headers: agent_with_role.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['open']).to eq(1)
      end
    end
  end
end
