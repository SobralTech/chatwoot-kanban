class Conversations::SearchSerializationData
  def initialize(conversations:)
    @conversations = conversations.to_a
  end

  def call
    return {} if conversations.empty?

    preload_conversation_associations
    messages = Message.where(
      account_id: conversations.map(&:account_id).uniq,
      conversation_id: conversations.map(&:id),
      private: false
    )
                      .where.not(message_type: :activity)
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

  private

  attr_reader :conversations

  def preload_conversation_associations
    ActiveRecord::Associations::Preloader.new(
      records: conversations,
      associations: [:inbox, :assignee_agent_bot, { assignee: { avatar_attachment: :blob } }, { contact: { avatar_attachment: :blob } }]
    ).call
  end

  def conversations_by_id
    @conversations_by_id ||= conversations.index_by(&:id)
  end
end
