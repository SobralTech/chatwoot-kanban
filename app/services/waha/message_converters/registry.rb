# Selects the converter for a WAHA payload by its normalized type: a real
# media message (matches Waha::MediaAttacher#media?, the same hasMedia+url
# gate that already governed download/attach before this registry existed),
# a text body, or — for anything else, including an unsupported WhatsApp
# message type (poll, location, vCard, ...) and a known type with no usable
# payload — the visible fallback.
#
# GOWS rarely sets a top-level `type` string at all, so this leans on
# Waha::MediaAttacher's own engine-aware classification (_data.Message.<kind>,
# _data.Info.MediaType) rather than trusting that field in isolation.
class Waha::MessageConverters::Registry
  def self.for(channel:, payload:, terminal: nil)
    media_attacher = Waha::MediaAttacher.new(channel: channel, payload: payload, terminal: terminal)
    return Waha::MessageConverters::Media.new(channel: channel, payload: payload, media_attacher: media_attacher) if media_attacher.media?
    return Waha::MessageConverters::Text.new(channel: channel, payload: payload) if payload['body'].present?

    Waha::MessageConverters::Fallback.new
  end
end
