class Waha::HttpClient
  pattr_initialize [:channel!]

  def get(path)
    response = HTTParty.get(url(path), headers: headers)
    response.parsed_response
  end

  def post(path, body)
    response = HTTParty.post(url(path), headers: headers, body: body.to_json)
    response.parsed_response
  end

  private

  def url(path)
    "#{channel.waha_url.chomp('/')}/api/#{path}"
  end

  def headers
    { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{channel.api_key}" }
  end
end
