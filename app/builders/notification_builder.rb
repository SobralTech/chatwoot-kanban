class NotificationBuilder
  pattr_initialize [:notification_type!, :user!, :account!, :primary_actor!, :secondary_actor, :batch_context]

  def perform
    build_notification
  end

  private

  def current_user
    Current.user
  end

  def user_subscribed_to_notification?
    notification_setting = user.notification_settings.find_by(account_id: account.id)
    # added for the case where an assignee might be removed from the account but remains in conversation
    return false if notification_setting.blank?

    return true if notification_setting.public_send("email_#{notification_type}?")
    return true if notification_setting.public_send("push_#{notification_type}?")
    return true if notification_type == 'contact_message' && audio_contact_message_enabled?

    false
  end

  def build_notification
    return unless Notification.enabled_notification_type?(notification_type)
    return if skip_contact_message_notification?
    return if skip_due_to_muted_or_blocked_conversation?
    # respect conversation access (inbox/team membership and custom-role permissions)
    return unless user_can_access_conversation?

    user.notifications.create!(
      notification_type: notification_type,
      account: account,
      primary_actor: primary_actor,
      # secondary_actor is secondary_actor if present, else current_user
      secondary_actor: secondary_actor || current_user
    )
  end

  def skip_contact_message_notification?
    notification_type == 'contact_message' && !user_subscribed_to_notification?
  end

  def skip_due_to_muted_or_blocked_conversation?
    return true if primary_actor.notifications_muted?

    # skip notifications for blocked conversations except for user mentions
    primary_actor.contact.blocked? && notification_type != 'conversation_mention'
  end

  def user_can_access_conversation?
    conversation = primary_actor.is_a?(Conversation) ? primary_actor : primary_actor.try(:conversation)
    return true if conversation.blank?

    # batch_context is supplied when notifying many users about one conversation, so the
    # membership lookups below are resolved from memory instead of once per user.
    account_user = if batch_context
                     batch_context.account_user_for(user.id)
                   else
                     AccountUser.find_by(account_id: account.id, user_id: user.id)
                   end
    return false if account_user.blank?

    ConversationPolicy.new(
      { user: user, account: account, account_user: account_user, batch_context: batch_context },
      conversation
    ).show?
  end

  def audio_contact_message_enabled?
    selected_audio_notification_types.include?('contact_message')
  end

  def selected_audio_notification_types
    audio_alerts = Array(user.ui_settings['enable_audio_alerts']).flat_map { |value| value.to_s.split('+') }

    audio_alerts.filter_map do |value|
      normalize_audio_notification_type(value)
    end.uniq
  end

  def normalize_audio_notification_type(value)
    return if value.blank? || value == 'none' || value == 'false'
    return 'contact_message' if legacy_audio_alert_type?(value)
    return value if %w[contact_message conversation_mention].include?(value)

    nil
  end

  def legacy_audio_alert_type?(value)
    %w[all assigned mine notme unassigned true].include?(value)
  end
end
