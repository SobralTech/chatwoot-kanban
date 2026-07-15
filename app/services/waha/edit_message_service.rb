class Waha::EditMessageService
  pattr_initialize [:message!, :content!]

  # Pushes an edit to WhatsApp. WhatsApp keeps a single message across N edits,
  # so we always target the family anchor (the original message's source_id),
  # even when the agent edits a later mirror. The returning message.edited
  # webhook drives the local strike-through + new message.
  def perform
    response = http_client.request(:put, edit_path, { text: content })
    return if response.success?

    raise "WAHA edit failed (#{response.code}): #{response.body}"
  end

  private

  def edit_path
    "#{channel.session_name}/chats/#{chat_id}/messages/#{anchor_source_id}"
  end

  # edit_of points at the original message's source_id for every edit mirror;
  # a message that was never edited is its own anchor.
  def anchor_source_id
    message.additional_attributes['edit_of'].presence || message.source_id
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
