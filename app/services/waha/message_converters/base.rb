# Shared contract every WAHA message converter implements. The router
# (Waha::IncomingMessageService, Waha::HistoryMessageWriter) calls these
# methods without knowing which converter was selected, so adding a new type
# (tickets 19-22) never touches the router itself.
#
# `download` and `attach` only do real work for Waha::MessageConverters::Media
# (a pre-transaction network fetch, and the attachment side effect); every
# other converter accepts the no-op default.
class Waha::MessageConverters::Base
  def download; end

  def content
    nil
  end

  def metadata
    {}
  end

  def attach(message); end
end
