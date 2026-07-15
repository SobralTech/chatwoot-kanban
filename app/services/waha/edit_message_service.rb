class Waha::EditMessageService
  pattr_initialize [:message!, :content!]

  # Pushes an edit to WhatsApp. WhatsApp keeps a single message across N edits,
  # so we always target the family anchor (the original message's source_id),
  # even when the agent edits a later mirror. The returning message.edited
  # webhook drives the local strike-through + new message.
  def perform
    stash_editor
    response = http_client.request(:put, edit_path, { text: content })
    return if response.success?

    raise "WAHA edit failed (#{response.code}): #{response.body}"
  end

  private

  # The edit is applied locally only when the message.edited webhook round-trips
  # back — a context with no Current.user. Stash the agent who clicked edit on the
  # anchor record so the webhook can attribute the mirror to them instead of the
  # generic "Enviado pelo WhatsApp" label. It is cleared once consumed.
  def stash_editor
    return unless Current.user

    anchor_message.update!(
      content_attributes: anchor_message.content_attributes.merge('pending_edited_by_id' => Current.user.id)
    )
  end

  def edit_path
    "#{channel.session_name}/chats/#{chat_id}/messages/#{anchor_source_id}"
  end

  # The webhook finds the edited message by the original stanza, so the editor
  # must be stashed on that same anchor record (which may differ from the mirror
  # the agent clicked when the message had already been edited before).
  def anchor_message
    @anchor_message ||= if message.additional_attributes['edit_of'].present?
                          message.inbox.messages.find_by(source_id: anchor_source_id)
                        else
                          message
                        end
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
