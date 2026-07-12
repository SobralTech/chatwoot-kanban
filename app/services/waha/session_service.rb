class Waha::SessionService
  pattr_initialize [:channel!]

  def start
    http_client.post("sessions/#{channel.session_name}/start", {})
  rescue StandardError => e
    Rails.logger.error "[WAHA] Failed to start session #{channel.session_name}: #{e.message}"
  end

  def qr_code
    http_client.get("#{channel.session_name}/auth/qr?format=base64")
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

  private

  def http_client
    @http_client ||= Waha::HttpClient.new(channel: channel)
  end
end
