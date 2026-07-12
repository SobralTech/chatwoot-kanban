class Waha::HttpClient
  pattr_initialize [:channel!]

  def get(path)
    request(:get, path).parsed_response
  end

  def post(path, body)
    request(:post, path, body).parsed_response
  end

  def request(method, path, body = nil)
    options = { headers: headers }
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
