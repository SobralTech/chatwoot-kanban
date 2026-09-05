# A shared static or live location. GOWS ships the raw whatsmeow proto node
# under `_data.Message.locationMessage` / `liveLocationMessage`; WAHA also
# normalizes both, for every engine, into the top-level `location` object. The
# raw node is the GOWS contract and the normalized one covers the rest.
#
# Rendered through Chatwoot's native `location` attachment — the same one
# Twilio, Telegram and WhatsApp Cloud already use — so the existing
# LocationBubble shows the title and a "See on map" action with no frontend
# change. The message deliberately keeps no body: that bubble only renders for
# a message without content, so every detail the payload carried goes into the
# attachment's title instead.
class Waha::MessageConverters::Location < Waha::MessageConverters::Base
  MAPS_URL = 'https://www.google.com/maps?q=%<latitude>s,%<longitude>s'.freeze

  pattr_initialize [:location!]

  # Returns the normalized location, or nil when the payload declares one but
  # carries no usable coordinates — the registry then falls through to the
  # visible fallback rather than persisting a location with no position.
  def self.extract(payload)
    location = from_gows(payload) || from_waha(payload)
    return nil if location.nil? || location[:latitude].blank? || location[:longitude].blank?

    location
  end

  # `URL` and `JPEGThumbnail` keep the proto's acronym casing in GOWS; only the
  # message-type keys are lower camel case.
  def self.from_gows(payload)
    message = payload.dig('_data', 'Message')
    return nil unless message.is_a?(Hash)

    static = message['locationMessage']
    return proto_location(static, live: false, description: static['comment']) if static.is_a?(Hash)

    live = message['liveLocationMessage']
    proto_location(live, live: true, description: live['caption']) if live.is_a?(Hash)
  end

  def self.proto_location(node, live:, description:)
    {
      live: live,
      latitude: node['degreesLatitude'],
      longitude: node['degreesLongitude'],
      name: node['name'],
      address: node['address'],
      url: node['URL'],
      description: description
    }
  end

  def self.from_waha(payload)
    node = payload['location']
    return nil unless node.is_a?(Hash)

    {
      live: node['live'].present?,
      latitude: node['latitude'],
      longitude: node['longitude'],
      name: node['name'],
      address: node['address'],
      url: node['url'],
      description: node['description']
    }
  end

  private_class_method :from_gows, :proto_location, :from_waha

  def attach(message)
    message.attachments.build(
      account_id: message.account_id,
      file_type: :location,
      coordinates_lat: location[:latitude].to_f,
      coordinates_long: location[:longitude].to_f,
      fallback_title: fallback_title,
      external_url: format(MAPS_URL, latitude: location[:latitude], longitude: location[:longitude])
    )
  end

  private

  # Most identifying first, coordinates always last so a location with no name
  # or address still shows where it is.
  def fallback_title
    [
      (I18n.t('conversations.messages.waha_location.live') if location[:live]),
      location[:name],
      location[:address],
      location[:description],
      location[:url],
      "#{location[:latitude]}, #{location[:longitude]}"
    ].compact_blank.join(' · ')
  end
end
