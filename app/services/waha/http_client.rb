class Waha::HttpClient
  # Ceiling so a slow/hanging WAHA call (e.g. a history page with downloadMedia)
  # raises instead of blocking a worker forever.
  DEFAULT_TIMEOUT = 90

  pattr_initialize [:channel!]

  def get(path)
    request(:get, path).parsed_response
  end

  def post(path, body)
    request(:post, path, body).parsed_response
  end

  def request(method, path, body = nil)
    options = { headers: headers, timeout: DEFAULT_TIMEOUT }
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
