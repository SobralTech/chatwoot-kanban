class Waha::SessionService
  pattr_initialize [:channel!]

  def start
    create_session
    http_client.request(:post, "sessions/#{channel.session_name}/start")
  rescue StandardError => e
    Rails.logger.error "[WAHA] Failed to start session #{channel.session_name}: #{e.message}"
  end

  def qr_code
    response = http_client.request(:get, "#{channel.session_name}/auth/qr?format=image")
    return nil unless response.success?

    "data:image/png;base64,#{Base64.strict_encode64(response.body)}"
  rescue StandardError => e
    Rails.logger.error "[WAHA] Failed to fetch QR for #{channel.session_name}: #{e.message}"
    nil
  end

  def status
    http_client.get("sessions/#{channel.session_name}")
  rescue StandardError => e
    Rails.logger.error "[WAHA] Failed to fetch status for #{channel.session_name}: #{e.message}"
    nil
  end

  def delete_session
    http_client.request(:delete, "sessions/#{channel.session_name}")
  rescue StandardError => e
    Rails.logger.error "[WAHA] Failed to delete session #{channel.session_name}: #{e.message}"
  end

  private

  # Creates the WAHA session with our webhook configured. WAHA's /start endpoint
  # requires the session to already exist, so this must run first. Idempotent:
  # re-creating an existing session returns 4xx which we safely ignore.
  def create_session
    http_client.request(:post, 'sessions', session_payload)
  end

  def session_payload
    {
      name: channel.session_name,
      start: true,
      config: {
        webhooks: [
          { url: channel.webhook_url, events: %w[message.any message.ack session.status] }
        ]
      }
    }
  end

  def http_client
    @http_client ||= Waha::HttpClient.new(channel: channel)
  end
end
