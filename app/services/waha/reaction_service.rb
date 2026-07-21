class Waha::ReactionService
  pattr_initialize [:message!, :emoji!]

  # Pushes a reaction to WhatsApp. The business number has a single reaction
  # slot per message, so a new emoji replaces the previous one and an empty
  # string removes it. Like edits, the chip and the activity are applied
  # locally only when the message.reaction webhook round-trips back — no
  # optimistic UI. The PUT always targets the family anchor (the real WhatsApp
  # message), never an edit mirror.
  def perform
    stash_reacting_agent
    response = http_client.request(:put, 'reaction', { messageId: anchor_source_id, reaction: emoji, session: channel.session_name })
    return if response.success?

    raise "WAHA reaction failed (#{response.code}): #{response.body}"
  end

  private

  # The returning webhook runs with no Current.user, so we stash the reacting
  # agent on the anchor and commit before the PUT — WAHA only emits the webhook
  # after processing the PUT, so the marker is always there when it lands.
  # ReactionApplier consumes and clears it.
  def stash_reacting_agent
    return unless Current.user

    anchor_message.update!(
      content_attributes: anchor_message.content_attributes.merge('pending_reaction_agent_id' => Current.user.id)
    )
  end

  # The webhook resolves the reaction by the original stanza, so the marker must
  # sit on that same anchor record (which may differ from the mirror the agent
  # clicked when the message had been edited).
  def anchor_message
    @anchor_message ||= if message.additional_attributes['edit_of'].present?
                          message.inbox.messages.find_by(source_id: anchor_source_id)
                        else
                          message
                        end
  end

  def anchor_source_id
    message.additional_attributes['edit_of'].presence || message.source_id
  end

  def channel
    @channel ||= message.inbox.channel
  end

  def http_client
    @http_client ||= Waha::HttpClient.new(channel: channel)
  end
end
