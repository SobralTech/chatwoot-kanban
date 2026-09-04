# Advisory locking for WAHA channels and chats.
#
# Serializes incoming webhooks, history import workers and contact operations
# on a per-(channel, chat) basis using PostgreSQL transaction advisory locks.
# Because locks are held on the database transaction and released on commit or
# rollback, crashes or timeouts never leave orphan locks in Redis or memory.
module Waha::Locking
  module_function

  def with_chat_lock(channel, chat_jids)
    channel_id = channel.is_a?(Channel::Waha) ? channel.id : channel
    jids = Array(chat_jids).compact.map(&:to_s).reject(&:blank?).uniq.sort
    return yield if channel_id.blank? || jids.empty?

    ActiveRecord::Base.transaction do
      jids.each do |chat_jid|
        key = "waha-chat:#{channel_id}:#{chat_jid}"
        quoted_key = ActiveRecord::Base.connection.quote(key)
        ActiveRecord::Base.connection.execute("SELECT pg_advisory_xact_lock(hashtextextended(#{quoted_key}, 0))")
      end
      yield
    end
  end
end
