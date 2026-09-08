class Waha::MediaAttacher
  MEDIA_KINDS = %w[image audio ptt video document sticker].freeze

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

  # A 5xx, timeout or connection failure is worth retrying — the file is still
  # there, WAHA/the network just hiccuped. Anything else (404/expired media,
  # a malformed URL, too many redirects) will fail the same way again, so it
  # is treated as terminal instead of retried.
  TRANSIENT_DOWNLOAD_ERRORS = [Down::ServerError, Down::ConnectionError, Down::SSLError].freeze

  pattr_initialize [:channel!, :payload!, :terminal]

  # Records a visible, permanent marker on a message whose media could not be
  # recovered (download exhausted its retries, or failed for a non-transient
  # reason) so the content never just silently disappears.
  def self.mark_download_failed(message)
    message.content_attributes = message.content_attributes.merge('media_download_failed' => true)
    message.content = I18n.t('conversations.messages.waha_media_unavailable') if message.content.blank?
  end

  # Fetches the media ahead of time so callers can keep the (potentially slow)
  # network round-trip outside their database transaction. Idempotent.
  #
  # `terminal` short-circuits straight to a miss without hitting the network —
  # set by a caller that already knows (from a prior raised MediaDownloadError)
  # that retries are exhausted, so it can persist the message with a fallback
  # instead of trying the same doomed request again.
  def download
    return @file if defined?(@file)
    return @file = nil unless media?
    return @file = nil if terminal

    @file = Down.download(
      media_url,
      headers: { 'X-Api-Key' => channel.api_key },
      open_timeout: 10, read_timeout: 60
    )
    observe(:success, kind: media_kind)
    @file
  rescue *TRANSIENT_DOWNLOAD_ERRORS => e
    raise CustomExceptions::Waha::MediaDownloadError, "WAHA media download failed for #{payload['id']}: #{e.message}"
  rescue StandardError => e
    # Not worth retrying (expired media, a malformed URL): the caller gets a nil
    # file and marks the message, so this is where the attempt ends.
    observe(:terminal, level: :error, reason: :not_retryable, error: e.class.name)
    @file = nil
  end

  def attach_to(message)
    file = download
    return self.class.mark_download_failed(message) if file.blank? && media?
    return if file.blank?

    message.attachments.build(
      account_id: message.account_id,
      file_type: map_file_type(media_kind),
      file: {
        io: file,
        filename: file.original_filename,
        content_type: file.content_type
      }
    )
    # Stickers are stored as image attachments (for gallery/download reuse) but
    # flagged via content_type so the UI can render them with the compact,
    # background-less sticker bubble instead of a full-size image.
    message.content_type = :sticker if media_kind == 'sticker'
  end

  # Kept public so history import eligibility and attachment persistence use the
  # same engine-aware classification. With downloadMedia=false WAHA still sends
  # the mimetype, which is the final fallback when raw engine fields are absent.
  def media_kind
    return @media_kind if defined?(@media_kind)

    raw = payload['type'].presence ||
          payload.dig('_data', 'Info', 'MediaType').presence ||
          infer_media_kind_from_data
    normalized = raw&.to_s&.downcase
    @media_kind = MEDIA_KINDS.include?(normalized) ? normalized : media_kind_from_mimetype
  end

  # Whether this payload actually carries downloadable media — the same gate
  # `download`/`attach_to` use internally. Public so the converter registry can
  # classify a payload as media without duplicating this check.
  def media?
    payload['hasMedia'].present? && media_url.present?
  end

  private

  # The download itself is the unit an administrator counts, so success and
  # terminal give-up are reported from here; a transient failure is reported by
  # whichever caller owns its retry budget (the live event job or the history
  # media job), which is the only place that knows how many tries are left.
  def observe(outcome, level: :debug, **context)
    Waha::Telemetry.emit(
      :media_download, channel: channel, chat: payload.dig('_data', 'Info', 'Chat'), level: level, outcome: outcome,
                       waha_id: Waha::Anchoring.stanza_of(payload['id']).presence, **context
    )
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

  def media_kind_from_mimetype
    case payload.dig('media', 'mimetype').to_s.downcase.split('/').first
    when 'image' then 'image'
    when 'audio' then 'audio'
    when 'video' then 'video'
    when 'application', 'text' then 'document'
    end
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
