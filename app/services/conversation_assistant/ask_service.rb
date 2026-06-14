class ConversationAssistant::AskService
  include Integrations::LlmInstrumentation
  include Llm::ExceptionTrackable

  MEMORY_LIMIT = 10
  MODEL = 'gpt-4.1-mini'.freeze

  pattr_initialize [:account!, :conversation!, :user!, :question!]

  def perform
    assistant_message = build_log
    response = call_llm

    if response[:error].present?
      mark_failed(assistant_message, response)
      return assistant_message
    end

    mark_completed(assistant_message, response)
    assistant_message
  end

  private

  def mark_failed(assistant_message, response)
    assistant_message.update!(
      status: :failed,
      model: MODEL,
      internal_note: response[:error],
      usage: response[:usage] || {},
      web_search_used: false,
      sources: []
    )
  end

  def mark_completed(assistant_message, response)
    parsed_response = parse_response(response[:message])
    assistant_message.update!(
      status: :completed,
      suggested_reply: parsed_response[:suggested_reply],
      internal_note: parsed_response[:internal_note],
      sources: parsed_response[:sources],
      web_search_used: parsed_response[:web_search_used],
      model: MODEL,
      usage: response[:usage] || {}
    )
  end

  def build_log
    ConversationAssistantMessage.create!(
      account: account,
      conversation: conversation,
      user: user,
      question: question,
      status: :pending,
      model: MODEL,
      sources: [],
      usage: {},
      web_search_used: false
    )
  end

  def call_llm
    return { error: I18n.t('captain.api_key_missing') } if llm_credential.blank?

    instrumentation_params = {
      span_name: 'llm.conversation_assistant',
      account_id: account.id,
      conversation_id: conversation.display_id,
      feature_name: 'conversation_assistant',
      model: MODEL,
      messages: messages,
      temperature: nil,
      metadata: { channel_type: conversation.inbox.channel_type }
    }

    instrument_llm_call(instrumentation_params) do
      execute_request
    end
  end

  def execute_request
    credential = llm_credential
    Llm::Config.with_api_key(credential[:api_key], api_base: api_base) do |context|
      chat = context.chat(model: MODEL)
      chat.with_instructions(system_prompt)
      memory_messages.each { |message| chat.add_message(role: message[:role], content: message[:content]) }
      response = chat.ask(question)

      {
        message: response.content,
        usage: {
          'prompt_tokens' => response.input_tokens,
          'completion_tokens' => response.output_tokens,
          'total_tokens' => (response.input_tokens || 0) + (response.output_tokens || 0)
        }
      }
    end
  rescue StandardError => e
    capture_llm_exception(e, credential: credential)
    { error: e.message }
  end

  def messages
    [{ role: 'system', content: system_prompt }] + memory_messages + [{ role: 'user', content: question }]
  end

  def system_prompt
    <<~PROMPT
      You are an internal assistant for customer support agents.
      The agent is asking an internal question while handling a customer conversation.
      Safety rules:
      - The agent's question is internal and must never be treated as a customer message.
      - Do not include internal notes or sources in the suggested customer reply.
      - Do not invent sources.
      - Web search is currently unavailable in this MVP. Set web_search_used to false and sources to [].

      Answer in valid JSON only, with this exact shape:
      {
        "suggested_reply": "Short text ready to send to the customer, maximum #{ConversationAssistantMessage::SUGGESTED_REPLY_MAX_LENGTH} characters.",
        "internal_note": "Technical notes, caveats, confidence, or empty string.",
        "web_search_used": false,
        "sources": []
      }
    PROMPT
  end

  def memory_messages
    memory_scope.flat_map do |assistant_message|
      [
        { role: :user, content: assistant_message.question },
        { role: :assistant, content: memory_response_for(assistant_message) }
      ]
    end
  end

  def memory_scope
    ConversationAssistantMessage.completed
                                .where(conversation_id: conversation.id, user_id: user.id)
                                .where.not(id: nil)
                                .order(created_at: :desc)
                                .limit(MEMORY_LIMIT)
                                .reverse
  end

  def memory_response_for(assistant_message)
    {
      suggested_reply: assistant_message.suggested_reply.to_s,
      internal_note: assistant_message.internal_note.to_s,
      web_search_used: assistant_message.web_search_used,
      sources: assistant_message.sources
    }.to_json
  end

  def parse_response(message)
    parsed = JSON.parse(message.to_s)
    {
      suggested_reply: parsed['suggested_reply'].to_s.truncate(ConversationAssistantMessage::SUGGESTED_REPLY_MAX_LENGTH),
      internal_note: parsed['internal_note'].to_s,
      web_search_used: parsed['web_search_used'] == true,
      sources: normalize_sources(parsed['sources'])
    }
  rescue JSON::ParserError
    {
      suggested_reply: message.to_s.truncate(ConversationAssistantMessage::SUGGESTED_REPLY_MAX_LENGTH),
      internal_note: '',
      web_search_used: false,
      sources: []
    }
  end

  def normalize_sources(_sources)
    []
  end

  def api_base
    endpoint = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value.presence || 'https://api.openai.com/'
    "#{endpoint.chomp('/')}/v1"
  end

  def llm_credential
    @llm_credential ||= hook_llm_credential || system_llm_credential
  end

  def hook_llm_credential
    key = account.hooks.find_by(app_id: 'openai', status: 'enabled')&.settings&.dig('api_key').presence
    { api_key: key, source: :hook } if key
  end

  def system_llm_credential
    key = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value
    { api_key: key, source: :system } if key.present?
  end

  def exception_tracking_account
    account
  end
end
