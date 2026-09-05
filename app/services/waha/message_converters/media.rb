# Image, audio, PTT, video, document or sticker. Delegates entirely to the
# Waha::MediaAttacher the registry already built to classify the payload, so
# download timing, the sticker content_type override, and the terminal
# "media_download_failed" fallback stay exactly as they were before the
# registry existed.
class Waha::MessageConverters::Media < Waha::MessageConverters::Base
  pattr_initialize [:channel!, :payload!, :media_attacher!]

  def download
    media_attacher.download
  end

  # The body is the caption, if any — independent of the attachment itself.
  def content
    Waha::MentionResolver.new(channel: channel, payload: payload).resolve(payload['body'].presence)
  end

  def attach(message)
    media_attacher.attach_to(message)
  end

  def downloads_attachment?
    true
  end
end
