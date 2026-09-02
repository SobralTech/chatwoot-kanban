class KanbanProducts::SearchClient
  include HTTParty
  base_uri 'https://produtos-api.sobraltec.com.br'

  class ApiError < StandardError; end

  def search(text: nil, sku: nil, price_list: nil, limit: nil)
    payload = { query: text, sku: sku, price_list: price_list, limit: limit }.compact
    response = self.class.post('/products/search', body: payload.to_json, headers: request_headers)
    handle_response(response)
  end

  private

  def request_headers
    {
      'Content-Type' => 'application/json',
      'X-Agent-Token' => GlobalConfigService.load('KANBAN_PRODUCTS_API_TOKEN', '')
    }
  end

  def handle_response(response)
    raise ApiError, "Products API error: #{response.code}" unless response.success?

    response.parsed_response
  end
end
