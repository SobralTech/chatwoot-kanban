class Waha::ChatOverviewFetcher
  PAGE_SIZE = 50

  pattr_initialize [:channel!, :since]

  # Returns the in-scope chat JIDs across every overview page: DMs (@c.us/@lid)
  # always, groups (@g.us) only when enabled; root newsletter/status/broadcast
  # chats are explicitly skipped by Waha::InboundEventPolicy. With `since`, a
  # chat whose last message predates it is skipped too: it has nothing to import
  # in the window, and a periodic gap-fill would otherwise query every chat.
  # Groups come first — with a bounded worker pool claiming chats in this same
  # order, that's what gets imported first too.
  def all
    chat_ids = []
    inactive = 0
    offset = 0
    loop do
      page = fetch_page(offset)
      break if page.blank?

      in_scope = page.select { |chat| in_scope?(chat['id']) }
      active = in_scope.select { |chat| active_since?(chat) }
      inactive += in_scope.size - active.size
      chat_ids.concat(active.pluck('id'))
      break if page.size < PAGE_SIZE

      offset += PAGE_SIZE
    end
    Waha::Telemetry.emit(:import_chats_discovered, channel: channel, level: :info, chats: chat_ids.size, inactive: inactive)
    groups, others = chat_ids.partition { |id| Waha::Jid.group?(id) }
    groups + others
  end

  private

  def fetch_page(offset)
    http_client.get_array("#{channel.session_name}/chats/overview?limit=#{PAGE_SIZE}&offset=#{offset}")
  end

  def in_scope?(id)
    id.present? && Waha::InboundEventPolicy.message(id, groups_enabled: channel.groups_enabled).action == :represent
  end

  # GOWS reports lastMessage (timestamp in seconds) as null for a chat without
  # messages; anything without a timestamp is kept so nothing can be missed.
  def active_since?(chat)
    timestamp = chat.dig('lastMessage', 'timestamp')
    since.nil? || timestamp.blank? || timestamp.to_i >= since.to_i
  end

  def http_client
    @http_client ||= Waha::HttpClient.new(channel: channel)
  end
end
