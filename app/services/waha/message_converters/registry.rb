# Selects the converter for a WAHA payload by its normalized type: a shared
# location, one or more vCards, a real media message (matches
# Waha::MediaAttacher#media?, the same hasMedia+url gate that already governed
# download/attach before this registry existed), a text body, or — for anything
# else, including a still-unsupported WhatsApp message type (poll, list, event,
# ...) and a known type with no usable payload — the visible fallback.
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
    location = Waha::MessageConverters::Location.extract(payload)
    return Waha::MessageConverters::Location.new(location: location) if location

    vcards = Waha::MessageConverters::VCard.extract(payload)
    return Waha::MessageConverters::VCard.new(vcards: vcards) if vcards.present?

    media_attacher = Waha::MediaAttacher.new(channel: channel, payload: payload, terminal: terminal)
    return Waha::MessageConverters::Media.new(channel: channel, payload: payload, media_attacher: media_attacher) if media_attacher.media?
    return Waha::MessageConverters::Text.new(channel: channel, payload: payload) if payload['body'].present?

    Waha::MessageConverters::Fallback.new
  end

  private_class_method :content_converter
end
