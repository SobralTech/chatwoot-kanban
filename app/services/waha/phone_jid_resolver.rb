# Resolves the chat JID WhatsApp actually registered for a phone number.
# Brazilian numbers are the common trap: "+55 88 99246-0616" is often
# registered without the ninth digit ("558892460616@c.us"), and sending to the
# naive "5588992460616@c.us" makes WAHA answer HTTP 500.
class Waha::PhoneJidResolver
  pattr_initialize [:channel!, :phone_number!]

  def perform
    chat_id = check_exists['chatId']
    chat_id = http_client.get("#{channel.session_name}/lids/#{chat_id}")&.dig('pn') if Waha::Jid.lid?(chat_id)
    Waha::Jid.phone_jid(chat_id) || fallback_jid
  rescue CustomExceptions::Waha::ApiError => e
    Rails.logger.warn("[WAHA] could not resolve JID for #{digits}: #{e.message}")
    fallback_jid
  end

  private

  def check_exists
    http_client.get("contacts/check-exists?phone=#{digits}&session=#{channel.session_name}") || {}
  end

  def fallback_jid
    "#{digits}@c.us"
  end

  def digits
    phone_number.delete('+')
  end

  def http_client
    @http_client ||= Waha::HttpClient.new(channel: channel)
  end
end
