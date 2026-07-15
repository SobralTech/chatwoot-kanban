class Webhooks::WahaEventsJob < ApplicationJob
  queue_as :low

  # A delivery ack can arrive while the mirror (message.any) is still being
  # created — creating it takes ~1s (contact/conversation resolution) while the
  # ack is processed in milliseconds. We retry the ack a few times so it lands
  # after the message exists instead of being dropped.
  ACK_MAX_RETRIES = 3
  ACK_RETRY_DELAY = 3.seconds

  def perform(channel_id, params = {}, ack_retries = 0)
    channel = Channel::Waha.find_by(id: channel_id)
    return unless channel&.account&.active?

    route_event(channel, params, ack_retries)
  end

  private

  # We subscribe to message.any only (the superset of every message event) so
  # each message is processed exactly once, regardless of direction.
  def route_event(channel, params, ack_retries)
    case params['event'].to_s
    when 'message.any'
      handle_message(channel, params['payload'])
    when 'message.ack'
      handle_message_ack(channel, params, ack_retries)
    when 'message.edited'
      handle_message_edited(channel, params['payload'])
    when 'session.status'
      handle_session_status(channel, params['payload'])
    end
  end

  def handle_message(channel, payload)
    return if payload.blank?
    # Sent from Chatwoot via the WAHA API — the local message already exists (with
    # its source_id). Mirroring would duplicate it; acks drive its status.
    return if chatwoot_originated?(payload)

    # Already mirrored (dedup); acks drive its status from here on.
    return if find_message_by_source_id(channel, payload['id'])

    # Incoming from a contact (fromMe: false) or sent from the phone/WhatsApp app
    # directly (fromMe: true, source: app/web). Mirror both into Chatwoot.
    Waha::IncomingMessageService.new(channel: channel, payload: payload).perform
  end

  def chatwoot_originated?(payload)
    payload['fromMe'] && payload['source'] == 'api'
  end

  # Maps WhatsApp delivery acks to Chatwoot statuses so outgoing bubbles show the
  # right check state (sent → delivered → read), mirroring WhatsApp itself.
  def handle_message_ack(channel, params, retries)
    payload = params['payload']
    message = find_message_by_source_id(channel, payload&.dig('id'))
    return update_delivery_status(message, payload&.dig('ack')) if message

    # The mirror is likely still being created — retry so we don't drop the ack.
    return if retries >= ACK_MAX_RETRIES

    self.class.set(wait: ACK_RETRY_DELAY).perform_later(channel.id, params, retries + 1)
  end

  def update_delivery_status(message, ack)
    return unless message&.outgoing?

    new_status = ack_to_status(ack)
    return if new_status.nil? || status_downgrade?(message.status, new_status)

    message.update!(status: new_status)
  end

  def ack_to_status(ack)
    case ack
    when -1 then 'failed'
    when 1 then 'sent'
    when 2 then 'delivered'
    when 3, 4 then 'read'
    end
  end

  # Acks can arrive out of order; never move a message backwards (e.g. read → delivered).
  def status_downgrade?(current, new_status)
    return false if new_status == 'failed'

    rank = { 'sent' => 1, 'delivered' => 2, 'read' => 3 }
    rank.fetch(new_status, 0) <= rank.fetch(current, 0)
  end

  # A WhatsApp edit keeps the original in place; instead we strike the original
  # through (superseded flag, rendered as line-through) and post the new content
  # as a fresh message quoting the original — the "[✏️ Editada]" marker. Agent
  # edits made from Chatwoot round-trip through this same event (fromMe: true).
  def handle_message_edited(channel, payload)
    return if payload.blank?

    original = find_message_by_source_id(channel, payload['editedMessageId'])
    supersede_edit_family(channel, original) if original
    Waha::IncomingMessageService.new(channel: channel, payload: payload, edited_original: original).perform
  end

  # WhatsApp keeps a single message across N edits (all pointing at the original
  # stanza), but we mirror each edit as a fresh message. So on every edit we
  # strike through the whole prior family — the original plus any earlier edit
  # mirrors — leaving only the newest version un-struck as the current one.
  def supersede_edit_family(channel, original)
    messages = channel.inbox.messages
    family = messages.where(source_id: original.source_id)
                     .or(messages.where("additional_attributes->>'edit_of' = ?", original.source_id))
    family.find_each { |message| mark_superseded(message) }
  end

  def mark_superseded(message)
    return if message.additional_attributes['superseded']

    message.update!(additional_attributes: message.additional_attributes.merge('superseded' => true))
  end

  def handle_session_status(channel, payload)
    status = payload&.dig('status')
    return if status.blank?

    channel.update_session_status(status)
  end

  def find_message_by_source_id(channel, source_id)
    return if source_id.blank?

    stanza_id = source_id.to_s.split('_').last
    channel.inbox.messages.where('source_id LIKE ?', "%_#{stanza_id}").first
  end
end
