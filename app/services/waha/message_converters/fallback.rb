# Selected for any WAHA message payload the registry can't classify as text or
# media — an unsupported message type or a known type whose payload is otherwise
# empty (declared media with no
# hasMedia/url and no caption, or a Pix/album header stripped of its data).
# Renders through the same `is_unsupported` content_attribute other channels (e.g. TikTok) already
# use, so the frontend's existing UnsupportedBubble shows a generic, safe
# message — no raw payload or sensitive data ever reaches the client.
class Waha::MessageConverters::Fallback < Waha::MessageConverters::Base
  def metadata
    { is_unsupported: true }
  end
end
