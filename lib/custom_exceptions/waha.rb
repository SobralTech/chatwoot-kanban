module CustomExceptions::Waha
  class ApiError < StandardError; end
  class HistoryNotReady < StandardError; end
end
