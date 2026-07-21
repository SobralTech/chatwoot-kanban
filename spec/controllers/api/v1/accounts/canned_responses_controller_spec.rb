require 'rails_helper'

RSpec.describe 'Canned Responses API', type: :request do
  let(:account) { create(:account) }

  def serialized_response(canned_response)
    canned_response.as_json.merge(
      'steps' => canned_response.canned_response_steps.ordered.map do |step|
        step.as_json(methods: [:file_url, :file_name, :file_blob_id])
      end
    )
  end

  before do
    create(:canned_response, account: account, content: 'Hey {{ contact.name }}, Thanks for reaching out', short_code: 'name-short-code')
  end

  describe 'GET /api/v1/accounts/{account.id}/canned_responses' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/canned_responses"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :agent) }

      it 'returns all the canned responses' do
        get "/api/v1/accounts/#{account.id}/canned_responses",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body).to eq(account.canned_responses.map { |record| serialized_response(record) })
      end

      it 'returns all the canned responses the user searched for' do
        cr1 = account.canned_responses.first
        create(:canned_response, account: account, content: 'Great! Looking forward', short_code: 'short-code')
        cr2 = create(:canned_response, account: account, content: 'Thanks for reaching out', short_code: 'content-with-thanks')
        cr3 = create(:canned_response, account: account, content: 'Thanks for reaching out', short_code: 'Thanks')

        params = { search: 'thanks' }

        get "/api/v1/accounts/#{account.id}/canned_responses",
            params: params,
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body).to eq(
          [cr3, cr2, cr1].map { |record| serialized_response(record) }
        )
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/canned_responses' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/canned_responses"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :agent) }

      it 'creates a new canned response' do
        params = { short_code: 'short', content: 'content' }

        post "/api/v1/accounts/#{account.id}/canned_responses",
             params: params,
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(account.canned_responses.count).to eq(2)
      end

      it 'creates a quick send canned response with steps' do
        params = {
          canned_response: {
            short_code: 'quick',
            mode: 'quick_send',
            steps: [
              { step_type: 'text', content: 'First message', position: 0 },
              { step_type: 'text', content: 'Second message', position: 1 }
            ]
          }
        }

        post "/api/v1/accounts/#{account.id}/canned_responses",
             params: params,
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['mode']).to eq('quick_send')
        expect(response.parsed_body['steps'].pluck('content')).to eq(['First message', 'Second message'])
      end
    end
  end

  describe 'PUT /api/v1/accounts/{account.id}/canned_responses/:id' do
    let(:canned_response) { CannedResponse.last }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        put "/api/v1/accounts/#{account.id}/canned_responses/#{canned_response.id}"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :agent) }

      it 'updates an existing canned response' do
        params = { short_code: 'B' }

        put "/api/v1/accounts/#{account.id}/canned_responses/#{canned_response.id}",
            params: params,
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(canned_response.reload.short_code).to eq('B')
      end
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/canned_responses/:id' do
    let(:canned_response) { CannedResponse.last }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/canned_responses/#{canned_response.id}"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :agent) }

      it 'destroys the canned response' do
        delete "/api/v1/accounts/#{account.id}/canned_responses/#{canned_response.id}",
               headers: agent.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:success)
        expect(CannedResponse.count).to eq(0)
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/canned_responses/:id/send_response' do
    let(:agent) { create(:user, account: account, role: :agent) }
    let(:inbox) { create(:inbox, account: account) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox) }
    let(:canned_response) do
      account.canned_responses.build(mode: 'quick_send', content: 'First message', short_code: 'quick').tap do |record|
        record.canned_response_steps.build(step_type: 'text', content: 'First message', position: 0)
        record.canned_response_steps.build(step_type: 'text', content: 'Second message', position: 1)
        record.save!
      end
    end

    before do
      create(:inbox_member, inbox: inbox, user: agent)
    end

    it 'sends all quick send steps as separate outgoing messages' do
      post "/api/v1/accounts/#{account.id}/canned_responses/#{canned_response.id}/send_response",
           params: { conversation_id: conversation.display_id },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:success)
      expect(conversation.messages.outgoing.pluck(:content)).to eq(['First message', 'Second message'])
    end

    it 'does not send response to a restricted conversation without access' do
      authorized_agent = create(:user, account: account, role: :agent)
      create(:inbox_member, inbox: inbox, user: authorized_agent)
      conversation.update!(access_mode: :selected_agents)
      create(:conversation_access_user, account: account, conversation: conversation, user: authorized_agent)

      post "/api/v1/accounts/#{account.id}/canned_responses/#{canned_response.id}/send_response",
           params: { conversation_id: conversation.display_id },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(conversation.messages.outgoing).to be_empty
    end
  end
end
