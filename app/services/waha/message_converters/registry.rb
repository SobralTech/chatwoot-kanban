# Selects the converter for a WAHA payload by its normalized type: a shared
# location, one or more vCards, a poll, a list, an event, a Pix payment
# request, an album header, a real media message (matches
# Waha::MediaAttacher#media?, the same hasMedia+url gate that already governed
# download/attach before this registry existed), a text body, or — for
# anything else, including a still-unsupported WhatsApp message type and a
# known type with no usable payload — the visible fallback.
#
# GOWS rarely sets a top-level `type` string at all, so the structured types
# are recognized from the raw proto node under `_data.Message` (with WAHA's
# engine-agnostic top-level fields as the fallback), and media leans on
# Waha::MediaAttacher's own engine-aware classification rather than trusting
# that field in isolation.
#
# A Facebook/Instagram ad reply and an album's individual photo/video each
# wrap whichever converter their own content would otherwise get, instead of
# replacing it — the same idiom a reply to a status uses below.
class Waha::MessageConverters::Registry
  def self.for(channel:, payload:, terminal: nil)
    converter = content_converter(channel: channel, payload: payload, terminal: terminal)
    converter = wrap_facebook_ad(converter, payload)
    converter = wrap_album_item(converter, payload)
    return Waha::MessageConverters::StatusReply.new(inner: converter) if Waha::StatusContext.reply_to_status?(payload)

    converter
  end

  def self.content_converter(channel:, payload:, terminal:)
    structured = structured_converter(payload)
    return structured if structured

    media_attacher = Waha::MediaAttacher.new(channel: channel, payload: payload, terminal: terminal)
    return Waha::MessageConverters::Media.new(channel: channel, payload: payload, media_attacher: media_attacher) if media_attacher.media?
    return Waha::MessageConverters::Text.new(channel: channel, payload: payload) if payload['body'].present?

    # The one place a WhatsApp message type reaches the visible fallback, so it
    # is also the single signal for it — live, edited and historical alike. The
    # raw engine node is what is unsupported, but publishing it would be
    # publishing the message, so only its top-level key is reported.
    Waha::Telemetry.emit(
      :message_unsupported_type, channel: channel, level: :info, reason: unsupported_reason(payload),
                                 waha_id: Waha::Anchoring.stanza_of(payload['id']).presence
    )
    Waha::MessageConverters::Fallback.new
  end

  # Names the shape that could not be converted without quoting any of it: the
  # proto node GOWS sent, or the fact that it sent none.
  def self.unsupported_reason(payload)
    node = payload.dig('_data', 'Message')
    (node.is_a?(Hash) ? node.keys.first : nil).presence || payload['type'].presence || :empty_payload
  end

  def self.structured_converter(payload)
    location_converter(payload) || vcard_converter(payload) || poll_converter(payload) || list_converter(payload) ||
      event_converter(payload) || pix_converter(payload) || album_converter(payload)
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

  def self.pix_converter(payload)
    pix = Waha::MessageConverters::Pix.extract(payload)
    Waha::MessageConverters::Pix.new(pix: pix) if pix
  end

  def self.album_converter(payload)
    album = Waha::MessageConverters::Album.extract(payload)
    Waha::MessageConverters::Album.new(album: album) if album
  end

  # A Facebook/Instagram ad reply wraps whichever converter the payload's own
  # content would otherwise get (normally Text) instead of replacing it — see
  # Waha::MessageConverters::FacebookAd.
  def self.wrap_facebook_ad(converter, payload)
    ad = Waha::MessageConverters::FacebookAd.extract(payload)
    return converter unless ad

    Waha::MessageConverters::FacebookAd.new(inner: converter, ad: ad)
  end

  # One photo/video of an album wraps the ordinary media converter that would
  # otherwise handle it, tagging it back to its header — see
  # Waha::MessageConverters::AlbumItem.
  def self.wrap_album_item(converter, payload)
    album_id = Waha::MessageConverters::AlbumItem.extract(payload)
    return converter unless album_id

    Waha::MessageConverters::AlbumItem.new(inner: converter, album_id: album_id)
  end

  private_class_method :content_converter, :unsupported_reason, :structured_converter, :location_converter, :vcard_converter,
                       :poll_converter, :list_converter, :event_converter, :pix_converter, :album_converter, :wrap_facebook_ad,
                       :wrap_album_item
end
