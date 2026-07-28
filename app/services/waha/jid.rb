# WhatsApp JID parsing. A JID looks like "5511999999999@c.us",
# "5511999999999:23@s.whatsapp.net" or "1203630...@g.us" — the leading local
# part is the number, optionally suffixed with a device id after a colon.
module Waha::Jid
  module_function

  # "5511999999999:23@s.whatsapp.net" -> "5511999999999"
  def digits(jid)
    jid.to_s.split('@').first.to_s.split(':').first
  end

  def group?(jid)
    jid.to_s.end_with?('@g.us')
  end

  def lid?(jid)
    jid.to_s.end_with?('@lid')
  end
end
