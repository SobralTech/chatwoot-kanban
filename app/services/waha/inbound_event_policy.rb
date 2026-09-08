# Explicit, observable policy for inbound WAHA traffic that cannot be treated as
# an ordinary direct or group message. A decision intentionally does not include
# JIDs, call ids, or message content in its log line: the signal is operational,
# not a second store of customer data.
class Waha::InboundEventPolicy
  Decision = Data.define(:action, :reason)

  def self.message(chat_jid, groups_enabled: true)
    jid = chat_jid.to_s

    return Decision.new(:ignore, :status_broadcast_chat) if jid == 'status@broadcast'
    return Decision.new(:ignore, :newsletter_chat) if jid.end_with?('@newsletter')
    return Decision.new(:ignore, :broadcast_chat) if jid.end_with?('@broadcast')
    return Decision.new(:ignore, :groups_disabled) if jid.end_with?('@g.us') && !groups_enabled

    Decision.new(:represent, :direct_or_group_chat)
  end

  def self.call(payload)
    return Decision.new(:ignore, :group_call) if payload['isGroup']
    return Decision.new(:ignore, :missing_call_id) if payload['id'].blank?
    return Decision.new(:ignore, :missing_call_participant) if payload['from'].blank?

    Decision.new(:represent, :direct_call)
  end

  def self.observe(channel:, event:, decision:)
    return if decision.action == :represent

    Waha::Telemetry.emit(:event_ignored, channel: channel, level: :info, event: event, reason: decision.reason)
  end
end
