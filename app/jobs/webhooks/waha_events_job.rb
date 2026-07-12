class Webhooks::WahaEventsJob < ApplicationJob
  queue_as :low

  def perform(channel_id, params = {})
    channel = Channel::Waha.find_by(id: channel_id)
    return unless channel&.account&.active?

    event = params['event'].to_s

    case event
    when 'message'
      handle_incoming_message(channel, params['payload'])
    when 'message.any'
      handle_message_any(channel, params['payload'])
    when 'session.status'
      handle_session_status(channel, params['payload'])
    end
  end

  private

  def handle_incoming_message(channel, payload)
    return if payload.blank? || payload['fromMe']

    Waha::IncomingMessageService.new(channel: channel, payload: payload).perform
  end

  def handle_message_any(channel, payload)
    return unless payload&.dig('fromMe') && payload.dig('_data', 'source') == 'api'

    message = find_message_by_source_id(channel, payload['id'])
    message&.update!(status: :delivered)
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
