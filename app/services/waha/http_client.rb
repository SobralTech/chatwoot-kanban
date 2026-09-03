class Waha::HttpClient
  # Ceiling so a slow/hanging WAHA call (e.g. a history page with downloadMedia)
  # raises instead of blocking a worker forever.
  DEFAULT_TIMEOUT = 90

  pattr_initialize [:channel!]

  def get(path, timeout: nil)
    request(:get, path, timeout: timeout).parsed_response
  end

  def get_array(path, timeout: nil)
    response = request(:get, path, timeout: timeout)
    parsed_response = response.parsed_response

    unless response.success?
      message = parsed_response.is_a?(Hash) ? parsed_response['message'] || parsed_response['error'] : nil
      raise CustomExceptions::Waha::ApiError, ["WAHA request failed (HTTP #{response.code})", message].compact.join(': ')
    end

    return parsed_response if parsed_response.is_a?(Array)

    raise CustomExceptions::Waha::ApiError, "WAHA returned #{parsed_response.class.name} instead of an array"
  end

  def post(path, body)
    request(:post, path, body).parsed_response
  end

  def request(method, path, body = nil, timeout: nil)
    options = { headers: headers, timeout: timeout || DEFAULT_TIMEOUT }
    options[:body] = body.to_json if body
    HTTParty.send(method, url(path), options)
  end

  private

  def url(path)
    "#{channel.waha_url.chomp('/')}/api/#{path}"
  end

  def headers
    { 'Content-Type' => 'application/json', 'X-Api-Key' => channel.api_key }
  end
end
