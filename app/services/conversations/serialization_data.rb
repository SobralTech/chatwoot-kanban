class Conversations::SerializationData
  Result = Data.define(:last_messages, :last_non_activity_messages)

  def initialize(conversations:)
    @conversations = conversations.to_a
  end

  def call
    return Result.new(last_messages: {}, last_non_activity_messages: {}) if conversations.empty?

    preload_conversation_associations
    unread_counts = unread_counts_by_conversation
    conversations.each do |conversation|
      conversation.preloaded_unread_incoming_messages_count = unread_counts.fetch(conversation.id, 0)
    end

    Result.new(
      last_messages: latest_messages(base_messages),
      last_non_activity_messages: latest_messages(base_messages.where.not(message_type: :activity))
    )
  end

  private

  attr_reader :conversations

  def preload_conversation_associations
    associations = [
      :account, :account_pin, :assignee_agent_bot, :contact_inbox, :team,
      { assignee: { avatar_attachment: :blob } },
      { contact: { avatar_attachment: :blob } }
    ]
    associations.push(:applied_sla, :sla_events) if preload_sla_associations?

    ActiveRecord::Associations::Preloader.new(records: conversations, associations: associations).call
  end

  def preload_sla_associations?
    Conversation.reflect_on_association(:applied_sla) && conversations.any? { |conversation| conversation.account.feature_enabled?('sla') }
  end

  def base_messages
    Message.where(
      account_id: conversations.map(&:account_id).uniq,
      conversation_id: conversations.map(&:id)
    )
  end

  def latest_messages(scope)
    messages = scope
               .reorder(nil)
               .select('DISTINCT ON (messages.conversation_id) messages.*')
               .order('messages.conversation_id ASC, messages.created_at DESC')
               .preload({ sender: { avatar_attachment: :blob } }, { attachments: { file_attachment: :blob } })
               .index_by(&:conversation_id)

    messages.each_value do |message|
      message.association(:conversation).target = conversations_by_id.fetch(message.conversation_id)
    end
    messages
  end

  def unread_counts_by_conversation
    base_messages
      .incoming
      .reorder(nil)
      .joins(:conversation)
      .where('messages.created_at > conversations.agent_last_seen_at OR conversations.agent_last_seen_at IS NULL')
      .group(:conversation_id)
      .count
      .transform_values { |count| [count, 10].min }
  end

  def conversations_by_id
    @conversations_by_id ||= conversations.index_by(&:id)
  end
end
