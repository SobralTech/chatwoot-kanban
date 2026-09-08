module CustomExceptions::Waha
  class ApiError < StandardError; end
  class AmbiguousIdentity < StandardError; end
  class StaleImportWorker < StandardError; end

  # Worth retrying: the server errored or the request never got a response
  # (timeout, connection failure). A 4xx or a malformed body is a request/
  # contract problem that retrying will not fix, so it stays a plain ApiError.
  class TransientError < ApiError; end

  # A transient failure downloading a media file (incoming attachment). Kept
  # distinct from TransientError so the webhook job can retry a stalled media
  # download without also catching unrelated transient failures (e.g. contact
  # resolution) under the same rescue.
  class MediaDownloadError < TransientError; end
end
