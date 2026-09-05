# Selects the converter for a WAHA payload by its normalized type: a shared
# location, one or more vCards, a real media message (matches
# Waha::MediaAttacher#media?, the same hasMedia+url gate that already governed
# download/attach before this registry existed), a text body, or — for anything
# else, including a still-unsupported WhatsApp message type (PIX, Facebook ad,
# album, ...) and a known type with no usable payload — the visible fallback.
#
# GOWS rarely sets a top-level `type` string at all, so the structured types
# are recognized from the raw proto node under `_data.Message` (with WAHA's
# engine-agnostic top-level fields as the fallback), and media leans on
# Waha::MediaAttacher's own engine-aware classification rather than trusting
# that field in isolation.
#
# A reply to a status can carry any of those contents, so it wraps the
# converter chosen for the reply's own content instead of replacing it.
class Waha::MessageConverters::Registry
  def self.for(channel:, payload:, terminal: nil)
    converter = content_converter(channel: channel, payload: payload, terminal: terminal)
    return Waha::MessageConverters::StatusReply.new(inner: converter) if Waha::StatusContext.reply_to_status?(payload)

    converter
  end

  def self.content_converter(channel:, payload:, terminal:)
    structured = structured_converter(payload)
    return structured if structured

    media_attacher = Waha::MediaAttacher.new(channel: channel, payload: payload, terminal: terminal)
    return Waha::MessageConverters::Media.new(channel: channel, payload: payload, media_attacher: media_attacher) if media_attacher.media?
    return Waha::MessageConverters::Text.new(channel: channel, payload: payload) if payload['body'].present?

    Waha::MessageConverters::Fallback.new
  end

  def self.structured_converter(payload)
    location_converter(payload) || vcard_converter(payload) || poll_converter(payload) || list_converter(payload) || event_converter(payload)
  end

  def self.location_converter(payload)
    location = Waha::MessageConverters::Location.extract(payload)
    Waha::MessageConverters::Location.new(location: location) if location
  end

  def self.vcard_converter(payload)
    vcards = Waha::MessageConverters::VCard.extract(payload)
    Waha::MessageConverters::VCard.new(vcards: vcards) if vcards.present?
  end

  def self.poll_converter(payload)
    poll = Waha::MessageConverters::Poll.extract(payload)
    Waha::MessageConverters::Poll.new(poll: poll) if poll
  end

  def self.list_converter(payload)
    list = Waha::MessageConverters::List.extract(payload)
    Waha::MessageConverters::List.new(list: list) if list
  end

  def self.event_converter(payload)
    event = Waha::MessageConverters::Event.extract(payload)
    Waha::MessageConverters::Event.new(event: event) if event
  end

  private_class_method :content_converter, :structured_converter, :location_converter, :vcard_converter, :poll_converter, :list_converter,
                       :event_converter
end
