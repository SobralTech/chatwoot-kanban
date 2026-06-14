require 'rails_helper'

RSpec.describe ConversationAssistant::AskService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:question) { 'Esse roteador e Wi-Fi 6?' }
  let(:service) { described_class.new(account: account, conversation: conversation, user: user, question: question) }
  let(:responses_endpoint) { 'https://api.openai.com/v1/responses' }

  before do
    InstallationConfig.where(name: %w[CAPTAIN_OPEN_AI_API_KEY CAPTAIN_OPEN_AI_ENDPOINT]).delete_all
    create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'test-key')
  end

  describe '#perform' do
    it 'saves log with model, status, usage, sources and web_search_used' do
      stub_openai_response(
        output_text: {
          suggested_reply: 'Esse modelo possui suporte a Wi-Fi 6.',
          internal_note: 'Confirme a revisão exata do modelo.',
          web_search_used: false,
          sources: []
        }.to_json,
        usage: { 'input_tokens' => 10, 'output_tokens' => 5, 'total_tokens' => 15 }
      )

      assistant_message = service.perform

      expect(assistant_message).to be_completed
      expect(assistant_message.model).to eq('gpt-4.1-mini')
      expect(assistant_message.usage['total_tokens']).to eq(15)
      expect(assistant_message.sources).to eq([])
      expect(assistant_message.web_search_used).to be(false)
      expect(assistant_message.suggested_reply).to eq('Esse modelo possui suporte a Wi-Fi 6.')
    end

    it 'allows the model to decide web search automatically' do
      request = stub_openai_response(
        output_text: {
          suggested_reply: 'Resposta curta.',
          internal_note: '',
          web_search_used: false,
          sources: []
        }.to_json
      )

      service.perform

      expect(request).to have_been_requested
    end

    it 'marks general questions as not using web search when OpenAI does not call the tool' do
      stub_openai_response(
        output_text: {
          suggested_reply: 'Você pode explicar de forma simples que o produto atende ao uso básico.',
          internal_note: 'Resposta baseada em conhecimento geral.',
          web_search_used: false,
          sources: []
        }.to_json
      )

      assistant_message = service.perform

      expect(assistant_message.web_search_used).to be(false)
      expect(assistant_message.sources).to eq([])
    end

    it 'saves web search sources from response annotations' do
      stub_openai_response(
        output_text: {
          suggested_reply: 'Sim, esse toner é compatível com a impressora informada.',
          internal_note: 'Fonte oficial consultada.',
          web_search_used: true,
          sources: []
        }.to_json,
        annotations: [
          { 'type' => 'url_citation', 'title' => 'Manual oficial', 'url' => 'https://example.com/manual' }
        ],
        web_search_used: true
      )

      assistant_message = service.perform

      expect(assistant_message.web_search_used).to be(true)
      expect(assistant_message.sources).to eq([{ 'title' => 'Manual oficial', 'url' => 'https://example.com/manual' }])
    end

    it 'deduplicates sources and limits them to 5' do
      sources = [
        { 'title' => 'Manual A', 'url' => 'https://example.com/a' },
        { 'title' => 'Manual A duplicado', 'url' => 'https://example.com/a' },
        { 'title' => 'Manual B', 'url' => 'https://example.com/b' },
        { 'title' => 'Manual C', 'url' => 'https://example.com/c' },
        { 'title' => 'Manual D', 'url' => 'https://example.com/d' },
        { 'title' => 'Manual E', 'url' => 'https://example.com/e' },
        { 'title' => 'Manual F', 'url' => 'https://example.com/f' }
      ]
      stub_openai_response(
        output_text: {
          suggested_reply: 'Resposta com fontes.',
          internal_note: 'Fontes deduplicadas.',
          web_search_used: true,
          sources: sources
        }.to_json,
        annotations: sources,
        web_search_used: true
      )

      assistant_message = service.perform

      expect(assistant_message.sources.pluck('url')).to eq(
        %w[https://example.com/a https://example.com/b https://example.com/c https://example.com/d https://example.com/e]
      )
    end

    it 'stores a controlled error when the web search request fails' do
      stub_request(:post, responses_endpoint).to_return(
        status: 400,
        body: { error: { message: 'Tool web_search is not supported by this endpoint' } }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

      assistant_message = service.perform

      expect(assistant_message).to be_failed
      expect(assistant_message.internal_note).to eq('Tool web_search is not supported by this endpoint')
      expect(assistant_message.suggested_reply).to be_blank
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

  def stub_openai_response(output_text:, usage: {}, annotations: [], web_search_used: false)
    stub_request(:post, responses_endpoint)
      .with(
        headers: { 'Authorization' => 'Bearer test-key' }
      ) do |request|
        payload = JSON.parse(request.body)
        expect(payload['model']).to eq('gpt-4.1-mini')
        expect(payload['tool_choice']).to eq('auto')
        expect(payload['tools']).to include({ 'type' => 'web_search', 'search_context_size' => 'low' })
        true
      end
      .to_return(
        status: 200,
        body: responses_body(output_text: output_text, usage: usage, annotations: annotations, web_search_used: web_search_used).to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  def responses_body(output_text:, usage:, annotations:, web_search_used:)
    output = []
    output << { 'type' => 'web_search_call', 'status' => 'completed' } if web_search_used
    output << {
      'type' => 'message',
      'content' => [
        {
          'type' => 'output_text',
          'text' => output_text,
          'annotations' => annotations
        }
      ]
    }

    {
      'id' => 'resp_test',
      'output' => output,
      'usage' => usage
    }
  end
end
