# One photo or video belonging to an album. GOWS tags it back to the album's
# header message via `messageContextInfo.messageAssociation` on the same
# content node that already carries the image/video itself — a sibling field,
# not a replacement for the caption/media the registry already resolved via
# Waha::MessageConverters::Media. So this wraps that converter exactly like
# StatusReply wraps a status reply's own content, and only tags the relation.
#
# The ORDER of an album's parts is not a separate field GOWS gives us — WhatsApp
# itself has none — so it is not synthesized here either. Each part keeps its
# own message timestamp (both live and, per Waha::HistoryMessageWriter,
# backdated history), and Chatwoot already lists messages by that timestamp,
# which is the same order the sender attached them in.
class Waha::MessageConverters::AlbumItem < Waha::MessageConverters::Base
  MEDIA_ALBUM = 'MEDIA_ALBUM'.freeze
  # The GOWS proto enum's own numeric value, kept as a fallback in case a build
  # ever serializes it as a plain integer instead of its canonical string name.
  MEDIA_ALBUM_NUMBER = 1

  pattr_initialize [:inner!, :album_id!]

  def self.extract(payload)
    association = payload.dig('_data', 'Message', 'messageContextInfo', 'messageAssociation')
    return unless association.is_a?(Hash) && album_association?(association['associationType'])

    association.dig('parentMessageKey', 'ID').presence
  end

  def self.album_association?(type)
    type.to_s.casecmp(MEDIA_ALBUM).zero? || type == MEDIA_ALBUM_NUMBER
  end
  private_class_method :album_association?

  def download
    inner.download
  end

  def content
    inner.content
  end

  def metadata
    inner.metadata.merge(album_id: album_id)
  end

  def attach(message)
    inner.attach(message)
  end

  def downloads_attachment?
    inner.downloads_attachment?
  end
end
