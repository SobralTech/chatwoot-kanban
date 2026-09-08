# Image, audio, PTT, video, document or sticker. Delegates entirely to the
# Waha::MediaAttacher the registry already built to classify the payload, so
# download timing, the sticker content_type override, and the terminal
# "media_download_failed" fallback stay exactly as they were before the
# registry existed. Historical media without a URL is represented as pending;
# the marker is removed by the phase-two fetcher when it resolves.
class Waha::MessageConverters::Media < Waha::MessageConverters::Base
  pattr_initialize [:channel!, :payload!, :media_attacher!, { pending: false }]

  def download
    media_attacher.download
  end

  # The body is the caption, if any — independent of the attachment itself.
  def content
    caption = resolved_caption
    return caption if caption.present?

    I18n.t('conversations.messages.waha_media_pending') if pending
  end

  def metadata
    return {} unless pending

    attrs = { media_download_pending: true, media_download_provenance: 'waha_history' }
    attrs[:media_download_content] = 'waha_media_pending' if resolved_caption.blank?
    attrs
  end

  def attach(message)
    media_attacher.attach_to(message)
  end

  def downloads_attachment?
    true
  end

  private

  def resolved_caption
    @resolved_caption ||= Waha::MentionResolver.new(channel: channel, payload: payload).resolve(payload['body'].presence)
  end
end
