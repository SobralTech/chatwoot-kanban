class Waha::SessionService
  pattr_initialize [:channel!]

  WEBHOOK_EVENTS = %w[message.any message.ack message.edited message.revoked session.status].freeze

  def start
    create_session
    http_client.request(:post, "sessions/#{channel.session_name}/start")
  rescue StandardError => e
    Rails.logger.error "[WAHA] Failed to start session #{channel.session_name}: #{e.message}"
  end

  # WAHA only applies session config on creation, so a session created before a
  # config change keeps its old webhook until we PUT the update. Given the GET
  # session response, this pushes our current webhook config only when it drifted,
  # avoiding needless session restarts on every status poll.
  def sync_webhook_config(session_info)
    return if webhook_current?(session_info)

    http_client.request(:put, "sessions/#{channel.session_name}", { config: { webhooks: [webhook_config] } })
  rescue StandardError => e
    Rails.logger.error "[WAHA] Failed to sync webhook for #{channel.session_name}: #{e.message}"
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

  def logout
    http_client.request(:post, "sessions/#{channel.session_name}/logout")
  rescue StandardError => e
    Rails.logger.error "[WAHA] Failed to logout session #{channel.session_name}: #{e.message}"
  end

  # Forces a fresh QR by always logging out and restarting the session, so the QR
  # appears in any prior state — including a "WORKING" session whose phone was
  # unlinked on the device. logout/create are idempotent, so a double click is safe.
  def reconnect
    logout
    start
  end

  private

  # Creates the WAHA session with our webhook configured. WAHA's /start endpoint
  # requires the session to already exist, so this must run first. Idempotent:
  # re-creating an existing session returns 4xx which we safely ignore.
  def create_session
    http_client.request(:post, 'sessions', session_payload)
  end

  def session_payload
    { name: channel.session_name, start: true, config: { webhooks: [webhook_config] } }
  end

  def webhook_config
    { url: channel.webhook_url, events: WEBHOOK_EVENTS }
  end

  # True when the running session already has our webhook URL subscribed to all
  # the events we depend on.
  def webhook_current?(session_info)
    webhooks = session_info.is_a?(Hash) ? session_info.dig('config', 'webhooks') : nil
    return false if webhooks.blank?

    webhooks.any? do |webhook|
      webhook['url'] == channel.webhook_url &&
        WEBHOOK_EVENTS.all? { |event| Array(webhook['events']).include?(event) }
    end
  end

  def http_client
    @http_client ||= Waha::HttpClient.new(channel: channel)
  end
end
