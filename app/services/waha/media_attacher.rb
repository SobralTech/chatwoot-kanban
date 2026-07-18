class Waha::MediaAttacher
  MEDIA_TYPES = %w[image document audio ptt video sticker].freeze
  # GOWS engine encodes media as raw `_data.Message.<kind>Message` keys; use this
  # mapping when neither `payload.type` nor `_data.Info.MediaType` is set.
  DATA_MESSAGE_KINDS = {
    'imageMessage' => 'image',
    'audioMessage' => 'audio',
    'pttMessage' => 'audio',
    'videoMessage' => 'video',
    'documentMessage' => 'document',
    'stickerMessage' => 'sticker'
  }.freeze

  pattr_initialize [:channel!, :payload!, :message!]

  def attach
    return unless media?

    file = Down.download(media_url, headers: { 'X-Api-Key' => channel.api_key })
    message.attachments.build(
      account_id: message.account_id,
      file_type: map_file_type(media_kind),
      file: {
        io: file,
        filename: file.original_filename,
        content_type: file.content_type
      }
    )
  rescue StandardError => e
    Rails.logger.error "[WAHA] Media download failed for #{payload['id']}: #{e.message}"
  end

  private

  def media?
    payload['hasMedia'].present? && media_url.present?
  end

  # WAHA WEBJS/WPP send `payload.mediaUrl` (deprecated) and `payload.media.url`;
  # GOWS sends only `payload.media.url`. Prefer the current field and fall back.
  # WAHA emits the URL with its internal host (e.g. `http://localhost:3000`), so
  # we rewrite the scheme+host+port to match the reachable `channel.waha_url`.
  def media_url
    return @media_url if defined?(@media_url)

    raw = payload.dig('media', 'url').presence || payload['mediaUrl'].presence
    @media_url = raw ? rebase_url(raw) : nil
  end

  def rebase_url(url)
    parsed = URI.parse(url)
    base = URI.parse(channel.waha_url)
    parsed.scheme = base.scheme
    parsed.host = base.host
    parsed.port = base.port
    parsed.to_s
  rescue URI::InvalidURIError
    url
  end

  # WAHA WEBJS/WPP set `payload.type` ("image", "audio", ...); GOWS omits it and
  # exposes the kind via `_data.Info.MediaType`, or lets us infer from the raw
  # `_data.Message` keys (imageMessage/audioMessage/...).
  def media_kind
    return @media_kind if defined?(@media_kind)

    raw = payload['type'].presence ||
          payload.dig('_data', 'Info', 'MediaType').presence ||
          infer_media_kind_from_data
    @media_kind = raw&.to_s&.downcase
  end

  def infer_media_kind_from_data
    data_message = payload.dig('_data', 'Message') || {}
    DATA_MESSAGE_KINDS.each { |key, kind| return kind if data_message[key] }
    nil
  end

  def map_file_type(kind)
    case kind
    when 'image', 'sticker' then :image
    when 'audio', 'ptt' then :audio
    when 'video' then :video
    else :file
    end
  end
end
