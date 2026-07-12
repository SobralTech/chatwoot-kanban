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
    when 'session.status'
      handle_session_status(channel, params['payload'])
    end
  end

  private

  def handle_message(channel, payload)
    return if payload.blank?

    if chatwoot_originated?(payload)
      # We sent this from Chatwoot via the WAHA API — the local message already
      # exists. Just confirm delivery; mirroring it would create a duplicate.
      message = find_message_by_source_id(channel, payload['id'])
      message&.update!(status: :delivered)
    else
      # Incoming from a contact (fromMe: false) or sent from the phone/WhatsApp
      # app directly (fromMe: true, source: app/web). Mirror both into Chatwoot.
      Waha::IncomingMessageService.new(channel: channel, payload: payload).perform
    end
  end

  def chatwoot_originated?(payload)
    payload['fromMe'] && payload['source'] == 'api'
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
