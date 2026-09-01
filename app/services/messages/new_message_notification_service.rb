class Messages::NewMessageNotificationService
  pattr_initialize [:message!]

  def perform
    return unless message.incoming? && message.notifiable?

    notify_inbox_members
  end

  private

  delegate :conversation, :sender, :account, to: :message

  def notify_inbox_members
    batch_context = ConversationPolicy::BatchContext.new(account, conversation)
    # Every notification below serializes this same conversation, so resolve the count once.
    conversation.preloaded_unread_incoming_messages_count = conversation.unread_incoming_messages.count

    conversation.inbox.members.find_each do |member|
      next if already_notified_user_ids.include?(member.id)

      NotificationBuilder.new(
        notification_type: 'contact_message',
        user: member,
        account: account,
        primary_actor: message.conversation,
        secondary_actor: message,
        batch_context: batch_context
      ).perform
    end
  end

  # The users could already have been notified via a mention
  # So we don't need to notify them again
  def already_notified_user_ids
    @already_notified_user_ids ||= conversation.notifications.where(secondary_actor: message).pluck(:user_id).to_set
  end
end
