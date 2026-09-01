require 'rails_helper'

RSpec.describe '/api/v1/widget/inbox_members', type: :request do
  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:agent_1) { create(:user, account: account) }
  let(:agent_2) { create(:user, account: account) }

  before do
    create(:inbox_member, user: agent_1, inbox: web_widget.inbox)
    create(:inbox_member, user: agent_2, inbox: web_widget.inbox)
  end

  describe 'GET /api/v1/widget/inbox_members' do
    let(:params) { { website_token: web_widget.website_token } }

    context 'with correct website token' do
      it 'returns the list of agents' do
        sql_queries = []
        callback = ->(_name, _start, _finish, _id, payload) { sql_queries << payload[:sql] if payload[:sql].present? }

        ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
          get '/api/v1/widget/inbox_members', params: params
        end

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body
        expect(json_response['payload'].length).to eq 2
        account_user_queries = sql_queries.count { |sql| sql.include?('FROM "account_users"') }
        expect(account_user_queries).to eq(1)
      end
    end

    context 'with invalid website token' do
      it 'returns the list of agents' do
        get '/api/v1/widget/inbox_members', params: { website_token: '' }
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
