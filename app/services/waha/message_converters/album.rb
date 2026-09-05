# The header WhatsApp sends before an album's individual photos/videos: just
# an announcement of how many of each are coming, with no media or caption of
# its own (that's why it's a full converter, not a wrapper — there is no inner
# content to preserve). The photos/videos that follow are ordinary media
# messages tagged back to this one by Waha::MessageConverters::AlbumItem.
class Waha::MessageConverters::Album < Waha::MessageConverters::Base
  pattr_initialize [:album!]

  def self.extract(payload)
    node = payload.dig('_data', 'Message', 'albumMessage')
    return unless node.is_a?(Hash)

    image_count = node['expectedImageCount'].to_i
    video_count = node['expectedVideoCount'].to_i
    return if image_count.zero? && video_count.zero?

    { expected_image_count: image_count, expected_video_count: video_count }
  end

  def content
    [I18n.t('conversations.messages.waha_album.header'), counts_line].compact_blank.join(' · ')
  end

  def metadata
    { album: album }
  end

  private

  def counts_line
    [
      (I18n.t('conversations.messages.waha_album.photos', count: album[:expected_image_count]) if album[:expected_image_count].positive?),
      (I18n.t('conversations.messages.waha_album.videos', count: album[:expected_video_count]) if album[:expected_video_count].positive?)
    ].compact_blank.join(', ')
  end
end
