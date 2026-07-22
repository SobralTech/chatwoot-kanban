module ReportVisibilityHelper
  private

  def visible_conversation_scope(conversation_scope)
    return conversation_scope if Current.user.blank? || Current.account_user&.administrator?

    Conversations::PermissionFilterService.new(conversation_scope, Current.user, account).access_list_restricted(conversation_scope)
  end

  def visible_conversation_ids
    visible_conversation_scope(account.conversations).select(:id)
  end

  def visible_message_scope(message_scope)
    return message_scope if Current.user.blank? || Current.account_user&.administrator?

    message_scope.where(conversation_id: visible_conversation_ids)
  end

  def visible_reporting_event_scope(event_scope)
    return event_scope if Current.user.blank? || Current.account_user&.administrator?

    event_scope.where(conversation_id: visible_conversation_ids)
  end
end
