class MessageWindowFinder
  DEFAULT_LIMIT = 20
  MAX_LIMIT = 50

  def initialize(conversation:, around:, before_limit: nil, after_limit: nil)
    @conversation = conversation
    @around = around
    @before_limit = clamp_limit(before_limit)
    @after_limit = clamp_limit(after_limit)
  end

  def perform
    before_messages + [anchor] + after_messages
  end

  private

  attr_reader :conversation, :around, :before_limit, :after_limit

  def anchor
    @anchor ||= conversation.messages.find(around)
  end

  def conversation_messages
    conversation.messages.includes(:attachments, :sender, sender: { avatar_attachment: [:blob] })
  end

  def before_messages
    conversation_messages
      .where('created_at < ? OR (created_at = ? AND id < ?)', anchor.created_at, anchor.created_at, anchor.id)
      .reorder(created_at: :desc, id: :desc)
      .limit(before_limit)
      .reverse
  end

  def after_messages
    conversation_messages
      .where('created_at > ? OR (created_at = ? AND id > ?)', anchor.created_at, anchor.created_at, anchor.id)
      .reorder(created_at: :asc, id: :asc)
      .limit(after_limit)
  end

  def clamp_limit(limit)
    return DEFAULT_LIMIT if limit.blank?

    limit.to_i.clamp(0, MAX_LIMIT)
  end
end
