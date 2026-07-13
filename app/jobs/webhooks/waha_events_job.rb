class Webhooks::WahaEventsJob < ApplicationJob
  queue_as :low

  def perform(channel_id, params = {})
    channel = Channel::Waha.find_by(id: channel_id)
    return unless channel&.account&.active?

    # We subscribe to message.any only (the superset of every message event) so
    # each message is processed exactly once, regardless of direction.
    case params['event'].to_s
    when 'message.any'
      handle_message(channel, params['payload'])
    when 'message.ack'
      handle_message_ack(channel, params['payload'])
    when 'session.status'
      handle_session_status(channel, params['payload'])
    end
  end

  private

  def handle_message(channel, payload)
    return if payload.blank?
    # Sent from Chatwoot via the WAHA API — the local message already exists (with
    # its source_id). Mirroring would duplicate it; acks drive its status.
    return if chatwoot_originated?(payload)

    # A re-emitted message.any for a message we already mirrored carries an updated
    # ack (this is how WAHA advances the status of phone-originated messages).
    # Advance the status instead of recreating the message.
    existing = find_message_by_source_id(channel, payload['id'])
    return update_delivery_status(existing, payload['ack']) if existing

    # Incoming from a contact (fromMe: false) or sent from the phone/WhatsApp app
    # directly (fromMe: true, source: app/web). Mirror both into Chatwoot.
    Waha::IncomingMessageService.new(channel: channel, payload: payload).perform
  end

  def chatwoot_originated?(payload)
    payload['fromMe'] && payload['source'] == 'api'
  end

  # Maps WhatsApp delivery acks to Chatwoot statuses so outgoing bubbles show the
  # right check state (sent → delivered → read), mirroring WhatsApp itself.
  def handle_message_ack(channel, payload)
    message = find_message_by_source_id(channel, payload&.dig('id'))
    update_delivery_status(message, payload&.dig('ack'))
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
