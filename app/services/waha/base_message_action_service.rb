# Shared plumbing for the agent-initiated actions we push to WhatsApp (edit,
# delete, reaction). All three target the family anchor rather than the mirror
# the agent clicked, and all three apply locally only when the matching webhook
# round-trips back.
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

  # The webhook resolves the message by the original stanza, so markers must sit
  # on that same anchor record — which differs from the mirror the agent clicked
  # when the message had already been edited before.
  def anchor_message
    @anchor_message ||= if message.additional_attributes['edit_of'].present?
                          message.inbox.messages.find_by(source_id: anchor_source_id)
                        else
                          message
                        end
  end

  def anchor_source_id
    Waha::Anchoring.anchor_source_id(message)
  end

  def message_path
    "#{channel.session_name}/chats/#{chat_id}/messages/#{anchor_source_id}"
  end

  def chat_id
    message.conversation.contact_inbox.source_id
  end

  def channel
    @channel ||= message.inbox.channel
  end

  def http_client
    @http_client ||= Waha::HttpClient.new(channel: channel)
  end
end
