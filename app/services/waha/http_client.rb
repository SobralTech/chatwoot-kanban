class Waha::HttpClient
  # Ceiling so a slow/hanging WAHA call (e.g. a history page with downloadMedia)
  # raises instead of blocking a worker forever.
  DEFAULT_TIMEOUT = 90

  # Connection-level failures worth retrying: the request never got a response.
  # A 4xx/5xx status is handled separately in #raise_for_status!.
  TRANSPORT_ERRORS = [
    Timeout::Error, Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::ETIMEDOUT,
    EOFError, SocketError, OpenSSL::SSL::SSLError, HTTParty::Error
  ].freeze

  # A session that is starting, restarting or briefly out of sync answers every
  # request with a 422 carrying this message, and recovers by itself. Treating
  # it as permanent fails a whole history import (and any send in flight) on a
  # blip a retry would have ridden out.
  SESSION_NOT_READY = /session status is not as expected/i

  pattr_initialize [:channel!]

  def get(path, timeout: nil)
    parsed_body(request(:get, path, timeout: timeout))
  end

  def get_array(path, timeout: nil)
    parsed = parsed_body(request(:get, path, timeout: timeout))
    return parsed if parsed.is_a?(Array)

    raise CustomExceptions::Waha::ApiError, "WAHA returned #{parsed.class.name} instead of an array"
  end

  def post(path, body)
    parsed_body(request(:post, path, body))
  end

  def request(method, path, body = nil, timeout: nil)
    raise CustomExceptions::Waha::ApiError, channel.connection_identity_error if channel.connection_identity_conflict?

    options = { headers: headers, timeout: timeout || DEFAULT_TIMEOUT }
    options[:body] = body.to_json if body
    response = HTTParty.send(method, url(path), options)
    raise_for_status!(response) unless response.success?
    response
  rescue *TRANSPORT_ERRORS => e
    raise CustomExceptions::Waha::TransientError, "WAHA request failed (transport): #{e.class}: #{e.message}"
  end

  private

  # 5xx is the server's own fault and worth retrying; any other non-2xx (4xx)
  # is a request/contract problem retrying will not fix — except the one 422
  # WAHA answers while the session is reconnecting, which resolves on its own.
  def raise_for_status!(response)
    detail = error_detail(response)
    message = ["WAHA request failed (HTTP #{response.code})", detail].compact.join(': ')
    error_class = transient_status?(response.code, detail) ? CustomExceptions::Waha::TransientError : CustomExceptions::Waha::ApiError
    raise error_class, message
  end

  def transient_status?(code, detail)
    code >= 500 || (code == 422 && detail.to_s.match?(SESSION_NOT_READY))
  end

  def error_detail(response)
    parsed = response.parsed_response
    parsed.is_a?(Hash) ? (parsed['message'] || parsed['error']) : nil
  rescue JSON::ParserError
    nil
  end

  def parsed_body(response)
    response.parsed_response
  rescue JSON::ParserError => e
    raise CustomExceptions::Waha::ApiError, "WAHA returned an invalid response body: #{e.message}"
  end

  def url(path)
    "#{channel.waha_url.chomp('/')}/api/#{path}"
  end

  def headers
    { 'Content-Type' => 'application/json', 'X-Api-Key' => channel.api_key }
  end
end
