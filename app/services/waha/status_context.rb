# Detects a reply to a WhatsApp status (story). The reply itself is an ordinary
# message in the direct chat — only the quoted message belongs to the status
# broadcast chat, which GOWS reports as `contextInfo.remoteJID` on the raw proto
# node under `_data.Message`. Status chats themselves are explicitly ignored by
# Waha::InboundEventPolicy, so the quoted story never exists locally and only
# the payload's own reply context can describe it.
module Waha::StatusContext
  STATUS_BROADCAST_JID = 'status@broadcast'.freeze

  def self.reply_to_status?(payload)
    return false if payload.dig('replyTo', 'id').blank?

    context_remote_jids(payload).include?(STATUS_BROADCAST_JID)
  end

  # GOWS keeps the acronym casing of the proto (`remoteJID`); NOWEB passes
  # Baileys' `remoteJid` through untouched.
  def self.context_remote_jids(payload)
    message = payload.dig('_data', 'Message')
    return [] unless message.is_a?(Hash)

    message.each_value.filter_map do |node|
      node.dig('contextInfo', 'remoteJID') || node.dig('contextInfo', 'remoteJid') if node.is_a?(Hash)
    end
  end

  private_class_method :context_remote_jids
end
