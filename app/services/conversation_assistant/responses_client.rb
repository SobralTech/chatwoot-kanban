class ConversationAssistant::ResponsesClient
  REQUEST_TIMEOUT_SECONDS = 30

  pattr_initialize [:api_key!, :api_base!, :model!, :messages!, { web_search: false }]

  def perform
    response = connection.post(responses_api_path) do |request|
      request.headers['Authorization'] = "Bearer #{api_key}"
      request.headers['Content-Type'] = 'application/json'
      request.body = payload.to_json
    end

    return build_error_response(response) unless response.success?

    build_success_response(JSON.parse(response.body))
  end

  private

  def connection
    Faraday.new do |faraday|
      faraday.options.timeout = REQUEST_TIMEOUT_SECONDS
      faraday.options.open_timeout = 5
    end
  end

  def responses_api_path
    "#{api_base}/responses"
  end

  def payload
    {
      model: model,
      input: messages.map { |message| responses_message(message) },
      max_output_tokens: 900,
      text: {
        format: {
          type: 'json_schema',
          name: 'conversation_assistant_response',
          strict: true,
          schema: response_schema
        }
      }
    }.merge(web_search_tools)
  end

  def web_search_tools
    return {} unless web_search

    { tools: [{ type: 'web_search', search_context_size: 'low' }], tool_choice: 'auto' }
  end

  def responses_message(message)
    text_type = message[:role].to_s == 'assistant' ? 'output_text' : 'input_text'

    {
      role: message[:role].to_s,
      content: [{ type: text_type, text: message[:content].to_s }]
    }
  end

  def response_schema
    properties = {
      suggested_reply: { type: 'string' },
      internal_note: { type: 'string' },
      web_search_used: { type: 'boolean' },
      sources: sources_schema
    }

    {
      type: 'object',
      additionalProperties: false,
      required: %w[suggested_reply internal_note web_search_used sources],
      properties: properties
    }
  end

  def sources_schema
    {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: %w[title url],
        properties: {
          title: { type: 'string' },
          url: { type: 'string' }
        }
      }
    }
  end

  def build_success_response(response_body)
    annotations = response_annotations(response_body)
    {
      message: output_text(response_body),
      usage: response_body['usage'] || {},
      web_search_used: web_search_used?(response_body, annotations),
      sources: annotations
    }
  end

  def build_error_response(response)
    error = JSON.parse(response.body)['error']['message']
    { error: error.presence || "OpenAI Responses API request failed with status #{response.status}" }
  rescue JSON::ParserError, NoMethodError
    { error: "OpenAI Responses API request failed with status #{response.status}" }
  end

  def output_text(response_body)
    return response_body['output_text'] if response_body['output_text'].present?

    response_body.fetch('output', []).filter_map do |item|
      next unless item['type'] == 'message'

      item.fetch('content', []).filter_map { |content| content['text'] }.join
    end.join
  end

  def response_annotations(response_body)
    response_body.fetch('output', []).flat_map do |item|
      item.fetch('content', []).flat_map { |content| content['annotations'] || [] }
    end
  end

  def web_search_used?(response_body, annotations)
    response_body.fetch('output', []).any? { |item| item['type'].to_s.include?('web_search') } ||
      annotations.any? { |annotation| annotation['type'].to_s.include?('url') }
  end
end
