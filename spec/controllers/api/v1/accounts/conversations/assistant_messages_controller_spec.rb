require 'rails_helper'

RSpec.describe 'Conversation Assistant Messages API', type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:agent) { create(:user, account: account, role: :agent) }

  before do
    create(:inbox_member, inbox: inbox, user: agent)
  end

  describe 'POST /api/v1/accounts/:account_id/conversations/:conversation_id/assistant_messages' do
    it 'allows an agent with conversation access to ask the assistant' do
      assistant_message = create(:conversation_assistant_message, account: account, conversation: conversation, user: agent)
      service = instance_double(ConversationAssistant::AskService, perform: assistant_message)
      allow(ConversationAssistant::AskService).to receive(:new).and_return(service)

      post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/assistant_messages",
           params: { question: 'Esse toner serve?' },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['id']).to eq(assistant_message.id)
      expect(ConversationAssistant::AskService).to have_received(:new).with(
        account: account,
        conversation: conversation,
        user: agent,
        question: 'Esse toner serve?'
      )
    end

    it 'fails for a conversation from another account' do
      other_account = create(:account)
      other_conversation = create(:conversation, account: other_account)

      post "/api/v1/accounts/#{account.id}/conversations/#{other_conversation.display_id}/assistant_messages",
           params: { question: 'Esse toner serve?' },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'fails when the question is longer than 2000 characters' do
      post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/assistant_messages",
           params: { question: 'a' * 2001 },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('Question is too long')
    end
  end

  describe 'POST /api/v1/accounts/:account_id/conversations/:conversation_id/assistant_messages/:id/send_to_customer' do
    let(:assistant_message) do
      create(
        :conversation_assistant_message,
        account: account,
        conversation: conversation,
        user: agent,
        suggested_reply: 'Resposta segura',
        internal_note: 'Nao enviar isso',
        sources: [{ 'title' => 'Fonte', 'url' => 'https://example.com' }]
      )
    end

    it 'sends only suggested_reply and updates sent_message_id' do
      post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/assistant_messages/#{assistant_message.id}/send_to_customer",
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:success)
      sent_message = conversation.messages.last
      expect(sent_message.content).to eq('Resposta segura')
      expect(sent_message.content).not_to include('Nao enviar isso')
      expect(sent_message.content).not_to include('example.com')
      expect(assistant_message.reload.sent_message_id).to eq(sent_message.id)
      expect(response.parsed_body['sent_message_id']).to eq(sent_message.id)
    end
  end
end
