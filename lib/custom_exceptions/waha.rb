module CustomExceptions::Waha
  class ApiError < StandardError; end
  class HistoryNotReady < StandardError; end

  # Worth retrying: the server errored or the request never got a response
  # (timeout, connection failure). A 4xx or a malformed body is a request/
  # contract problem that retrying will not fix, so it stays a plain ApiError.
  class TransientError < ApiError; end
end
