class ConversationMessageSearchFinder
  DEFAULT_LIMIT = 20
  MAX_LIMIT = 50

  def initialize(conversation, params)
    @conversation = conversation
    @params = params
  end

  def perform
    raise ArgumentError, 'Search query is required' if search_query.blank?

    {
      messages: paginated_messages,
      meta: {
        total_count: total_count,
        limit: limit,
        has_more: more_results?,
        next_before_id: next_before_id
      }
    }
  end

  private

  def base_query
    @base_query ||= begin
      messages = @conversation.messages.includes(:attachments, :sender, sender: { avatar_attachment: [:blob] })
      messages.where('unaccent(messages.content) ILIKE unaccent(:search)', search: "%#{search_query}%")
    end
  end

  def cursor_query
    return base_query if before_id.blank?

    base_query.where('messages.id < ?', before_id)
  end

  def fetched_messages
    @fetched_messages ||= cursor_query.reorder('messages.id DESC').limit(limit + 1).to_a
  end

  def paginated_messages
    fetched_messages.first(limit)
  end

  def total_count
    @total_count ||= base_query.count
  end

  def more_results?
    fetched_messages.length > limit
  end

  def next_before_id
    return unless more_results?

    paginated_messages.last&.id
  end

  def search_query
    @search_query ||= @params[:q].to_s.strip
  end

  def before_id
    @before_id ||= @params[:before_id].presence&.to_i
  end

  def limit
    @limit ||= begin
      requested_limit = @params[:limit].presence&.to_i || DEFAULT_LIMIT
      requested_limit.clamp(1, MAX_LIMIT)
    end
  end
end

ConversationMessageSearchFinder.prepend_mod_with('ConversationMessageSearchFinder')
