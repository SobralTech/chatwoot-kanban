class Waha::PresenceClient
  pattr_initialize [:channel!]

  def seen(chat_id, message_ids:)
    request(:seen, chat_id) do
      http_client.post('sendSeen', { session: channel.session_name, chatId: chat_id, messageIds: message_ids })
    end
  end

  def typing(chat_id)
    presence(chat_id, 'typing')
  end

  def paused(chat_id)
    presence(chat_id, 'paused')
  end

  def recording(chat_id)
    presence(chat_id, 'recording')
  end

  private

  def presence(chat_id, value)
    request(value, chat_id) do
      http_client.post("#{channel.session_name}/presence", { chatId: chat_id, presence: value })
    end
  end

  def request(action, chat_id)
    yield
  rescue StandardError => e
    Rails.logger.warn "[WAHA] presence #{action} failed for #{chat_id}: #{e.message}"
    nil
  end

  def http_client
    @http_client ||= Waha::HttpClient.new(channel: channel)
  end
end
