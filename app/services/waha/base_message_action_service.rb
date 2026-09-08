# Shared plumbing for the agent-initiated actions we push to WhatsApp (edit,
# delete, reaction). Replies, edits and reactions use the deterministic family
# anchor; delete can expand a multipart send to every confirmed external part.
# All three apply locally only when the matching webhook round-trips back.
class Waha::BaseMessageActionService
  private

  def dispatch!(verb, path, body = nil)
    response = http_client.request(verb, path, body)
    return if response.success?

    raise "WAHA #{verb} failed (#{response.code}): #{response.body}"
  end

  # The returning webhook runs with no Current.user, so we stash the acting agent
  # on the anchor record before the request — WAHA only emits the webhook after
  # processing it, so the marker is always there when it lands. The webhook
  # consumer clears it.
  def stash_current_user(key)
    return unless Current.user

    anchor_message.update!(content_attributes: anchor_message.content_attributes.merge(key => Current.user.id))
  end

  # Invalidates a marker stashed by stash_current_user when the request that
  # was supposed to consume it never made it to WAHA — otherwise it lingers on
  # the anchor and misattributes a later, unrelated event to this agent.
  def clear_marker(key)
    return unless anchor_message.content_attributes.key?(key.to_s)

    anchor_message.update!(content_attributes: anchor_message.content_attributes.except(key.to_s))
  end

  # The webhook resolves the message by the original stanza, so markers must sit
  # on that same anchor record — which differs from the mirror the agent clicked
  # when the message had already been edited before.
  def anchor_message
    @anchor_message ||= Waha::Anchoring.family_anchor_message(message)
  end

  def anchor_source_id
    Waha::Anchoring.external_anchor_source_id(message)
  end

  def message_path
    "#{channel.session_name}/chats/#{chat_id}/messages/#{anchor_source_id}"
  end

  def message_paths
    Waha::Anchoring.mappings_for(message).map do |mapping|
      "#{channel.session_name}/chats/#{mapping.chat_jid}/messages/#{mapping.provider_id}"
    end
  end

  def chat_id
    Waha::Anchoring.mappings_for(message).first&.chat_jid
  end

  def channel
    @channel ||= message.inbox.channel
  end

  def http_client
    @http_client ||= Waha::HttpClient.new(channel: channel)
  end
end
