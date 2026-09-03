class Waha::ChatOverviewFetcher
  PAGE_SIZE = 50

  pattr_initialize [:channel!]

  # Returns the in-scope chat JIDs across every overview page: DMs (@c.us/@lid)
  # always, groups (@g.us) only when enabled; newsletters/status are skipped.
  # Groups come first — with a bounded worker pool claiming chats in this same
  # order, that's what gets imported first too.
  def all
    chat_ids = []
    offset = 0
    loop do
      page = fetch_page(offset)
      break if page.blank?

      chat_ids.concat(page.filter_map { |chat| chat['id'] }.select { |id| in_scope?(id) })
      break if page.size < PAGE_SIZE

      offset += PAGE_SIZE
    end
    groups, others = chat_ids.partition { |id| Waha::Jid.group?(id) }
    groups + others
  end

  private

  def fetch_page(offset)
    http_client.get_array("#{channel.session_name}/chats/overview?limit=#{PAGE_SIZE}&offset=#{offset}")
  end

  def in_scope?(id)
    return false if Channel::Waha::IGNORED_CHAT_SUFFIXES.any? { |suffix| id.end_with?(suffix) }
    return channel.groups_enabled if Waha::Jid.group?(id)

    true
  end

  def http_client
    @http_client ||= Waha::HttpClient.new(channel: channel)
  end
end
