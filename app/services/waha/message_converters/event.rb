# A WhatsApp event invitation. GOWS supplies this as eventMessage under the
# raw proto node. We only render information present in that node; no RSVP or
# attendance state is inferred from the invitation itself.
class Waha::MessageConverters::Event < Waha::MessageConverters::Base
  pattr_initialize [:event!]

  def self.extract(payload)
    node = event_node(payload)
    return unless node.is_a?(Hash)

    title = node['name'].presence || node['title'].presence
    return if title.blank?

    event_from(node, title)
  end

  def self.event_node(payload)
    message = payload.dig('_data', 'Message')
    (message['eventMessage'] if message.is_a?(Hash)) || payload['event']
  end
  private_class_method :event_node

  def self.event_from(node, title)
    {
      title: title,
      description: node['description'].presence,
      start_time: node['startTime'].presence || node['start_time'].presence,
      end_time: node['endTime'].presence || node['end_time'].presence,
      location: location_from(node['location']),
      canceled: node['isCanceled'] || node['is_canceled']
    }.compact
  end
  private_class_method :event_from

  def content
    ([I18n.t('conversations.messages.waha_event.header'), event[:title]] + details).compact_blank.join("\n")
  end

  def metadata
    { event: event }
  end

  def self.location_from(location)
    return unless location.is_a?(Hash)

    [location['name'], location['address']].compact_blank.join(' · ').presence
  end
  private_class_method :location_from

  private

  def details
    [canceled_line, time_line(:starts_at, event[:start_time]), time_line(:ends_at, event[:end_time]), location_line, event[:description]]
  end

  def canceled_line
    I18n.t('conversations.messages.waha_event.canceled') if event[:canceled]
  end

  def time_line(key, timestamp)
    I18n.t("conversations.messages.waha_event.#{key}", time: format_time(timestamp)) if timestamp.present?
  end

  def location_line
    I18n.t('conversations.messages.waha_event.location', location: event[:location]) if event[:location].present?
  end

  # ISO 8601 is unambiguous across agent locales while still giving a readable
  # date, time and offset in a normal message bubble.
  def format_time(timestamp)
    (Time.zone&.at(timestamp.to_i) || Time.at(timestamp.to_i).utc).iso8601
  end
end
