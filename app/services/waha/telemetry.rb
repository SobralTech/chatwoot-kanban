# Operational signals for the WAHA integration: what an administrator needs to
# see to follow one event from reception to its final outcome, emitted through
# infrastructure this application already runs.
#
# Every signal goes to two places at once:
#
#   * `Rails.logger`, as a logfmt line, to read a single event's path.
#   * `ActiveSupport::Notifications`, as `waha.<signal>`, to count them. An
#     already-configured APM or StatsD subscriber turns these into metrics; the
#     integration itself neither ships, stores nor aggregates telemetry.
#
# The notification fires regardless of log level, so a signal is still counted
# when its line is below the configured threshold. Routine per-message signals
# therefore log at :debug — they are metrics first, log lines second — while
# retries, ignored events and terminal failures log at :warn/:error.
#
# Fields are split in two, and that split is the whole cardinality and privacy
# contract:
#
#   * TAG_KEYS are the only fields a metrics backend may use as dimensions.
#     Each is drawn from a closed vocabulary written in this codebase — a
#     webhook event name, a policy reason, an outcome — so no amount of traffic
#     can create unbounded series.
#   * Everything else is correlation context: account, inbox, channel, chat,
#     external message, internal message, part and attempt. It is logged and
#     carried on the notification payload, never used as a dimension.
#
# `waha_id` is the stanza — the engine's own message identifier with the chat
# and direction segments GOWS prefixes onto it stripped off (see
# Waha::Anchoring). It is the single value that follows one message from the
# live webhook, through history import and an outgoing delivery attempt, to its
# final delivery state, and unlike the full provider id it carries no phone
# number.
#
# No message body, caption, media URL, filename, contact name, phone number or
# raw JID is ever part of a signal, and no free-text error message: a failure
# reports its exception class, while the text stays where it is already
# persisted and access-controlled (`external_error`, `WahaDeliveryAttempt#
# last_error`, `WahaImportChat#error`, `import_state`). A chat appears as
# `chat_ref`, a stable truncated digest that correlates every line of one chat
# without publishing who it is with.
module Waha::Telemetry
  module_function

  TAG_KEYS = %i[signal event reason outcome direction kind part_type scope].freeze

  CHAT_REF_LENGTH = 12

  def emit(signal, channel: nil, chat: nil, level: :debug, **context)
    fields = correlation(signal, channel, chat).merge(context).compact
    ActiveSupport::Notifications.instrument("waha.#{signal}", fields.merge(tags: tags(fields)))
    Rails.logger.public_send(level) { "[WAHA] #{logfmt(fields)}" }
  end

  # `event` is the one tag whose vocabulary belongs to WAHA rather than to this
  # codebase, so tag values are reduced to a short token: a malformed or hostile
  # payload can still be counted, but it cannot inject an arbitrary series name.
  def tags(fields)
    fields.slice(*TAG_KEYS).transform_values { |value| value.to_s.downcase.gsub(/[^a-z0-9._-]/, '_').first(40) }
  end

  # A stable, non-reversible handle for one chat. Whether it is a group is
  # operational rather than personal, so it stays readable in front of the
  # digest.
  #
  # The phone forms of one identity are collapsed first, so `@s.whatsapp.net`,
  # a device-suffixed JID and `@c.us` all produce one handle. An `@lid` does
  # not collapse into its phone JID: that mapping lives in
  # waha_contact_aliases, and resolving it would put a database query behind
  # every log line. A chat therefore has one handle per identity form it is
  # observed under — on live GOWS traffic roughly a quarter of direct messages
  # arrive as `@lid` while their canonical mapping is `@c.us`. `waha_id` is the
  # join key across those forms, and signals emitted after contact resolution
  # (Waha::IncomingMessageService, Waha::SendOnWahaService) already pass the
  # canonical JID.
  def chat_ref(chat)
    return if chat.blank?

    normalized = Waha::Jid.phone_jid(chat) || chat.to_s
    "#{Waha::Jid.group?(normalized) ? 'g' : 'd'}-#{OpenSSL::Digest::SHA256.hexdigest(normalized)[0, CHAT_REF_LENGTH]}"
  end

  def correlation(signal, channel, chat)
    {
      signal: signal,
      account_id: channel&.account_id,
      inbox_id: channel&.inbox&.id,
      channel_id: channel&.id,
      # The join key to the WAHA server's own logs, which is what makes an
      # end-to-end trace possible at all. Operator configuration rather than
      # customer content, and context only — never a metric dimension.
      session: channel&.session_name,
      chat_ref: chat_ref(chat)
    }
  end

  def logfmt(fields)
    fields.map { |key, value| "#{key}=#{value}" }.join(' ')
  end
end
