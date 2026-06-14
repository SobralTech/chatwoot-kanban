require 'rails_helper'

RSpec.describe ConversationAssistant::AskService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:question) { 'Esse roteador e Wi-Fi 6?' }
  let(:service) { described_class.new(account: account, conversation: conversation, user: user, question: question) }

  describe '#perform' do
    before do
      allow(service).to receive(:call_llm).and_return(
        {
          message: {
            suggested_reply: 'Esse modelo possui suporte a Wi-Fi 6.',
            internal_note: 'Confirme a revisão exata do modelo.',
            web_search_used: false,
            sources: []
          }.to_json,
          usage: { 'prompt_tokens' => 10, 'completion_tokens' => 5, 'total_tokens' => 15 }
        }
      )
    end

    it 'saves log with model, status, usage, sources and web_search_used' do
      assistant_message = service.perform

      expect(assistant_message).to be_completed
      expect(assistant_message.model).to eq('gpt-4.1-mini')
      expect(assistant_message.usage['total_tokens']).to eq(15)
      expect(assistant_message.sources).to eq([])
      expect(assistant_message.web_search_used).to be(false)
      expect(assistant_message.suggested_reply).to eq('Esse modelo possui suporte a Wi-Fi 6.')
    end
  end

  describe 'memory' do
    let(:other_user) { create(:user, account: account, role: :agent) }
    let(:other_conversation) { create(:conversation, account: account, inbox: inbox) }

    before do
      create(
        :conversation_assistant_message,
        account: account,
        conversation: conversation,
        user: user,
        question: 'Pergunta da memoria',
        suggested_reply: 'Resposta da memoria'
      )
      create(
        :conversation_assistant_message,
        account: account,
        conversation: conversation,
        user: other_user,
        question: 'Pergunta de outro agente',
        suggested_reply: 'Resposta de outro agente'
      )
      create(
        :conversation_assistant_message,
        account: account,
        conversation: other_conversation,
        user: user,
        question: 'Pergunta de outra conversa',
        suggested_reply: 'Resposta de outra conversa'
      )
      create(:message, account: account, inbox: inbox, conversation: conversation, content: 'Mensagem publica do cliente')
      create(:message, account: account, inbox: inbox, conversation: conversation, content: 'Nota privada', private: true)
    end

    it 'uses only completed assistant messages for the same conversation and agent' do
      contents = service.send(:messages).pluck(:content).join("\n")

      expect(contents).to include('Pergunta da memoria')
      expect(contents).to include('Resposta da memoria')
      expect(contents).not_to include('Pergunta de outro agente')
      expect(contents).not_to include('Pergunta de outra conversa')
    end

    it 'does not include public or private customer conversation messages by default' do
      contents = service.send(:messages).pluck(:content).join("\n")

      expect(contents).not_to include('Mensagem publica do cliente')
      expect(contents).not_to include('Nota privada')
    end
  end
end
