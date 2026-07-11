module ReportHelper
  private

  def scope
    case params[:type]
    when :account
      account
    when :inbox
      inbox
    when :agent
      user
    when :label
      label
    when :team
      team
    end
  end

  def conversations_count
    (get_grouped_values conversations).count
  end

  def incoming_messages_count
    (get_grouped_values incoming_messages).count
  end

  def outgoing_messages_count
    (get_grouped_values outgoing_messages).count
  end

  def resolutions_count
    (get_grouped_values resolutions).count
  end

  def bot_resolutions_count
    (get_grouped_values bot_resolutions).count
  end

  def bot_handoffs_count
    (get_grouped_values bot_handoffs).count
  end

  def conversations
    visible_conversation_scope(scope.conversations.where(account_id: account.id, created_at: range))
  end

  def incoming_messages
    visible_message_scope(scope.messages.where(account_id: account.id, created_at: range).incoming.unscope(:order))
  end

  def outgoing_messages
    visible_message_scope(scope.messages.where(account_id: account.id, created_at: range).outgoing.unscope(:order))
  end

  def resolutions
    visible_reporting_event_scope(scope.reporting_events.where(account_id: account.id, name: :conversation_resolved, created_at: range))
  end

  def bot_resolutions
    events = scope.reporting_events.where(account_id: account.id, name: :conversation_bot_resolved, created_at: range)

    visible_reporting_event_scope(events).where.not(conversation_id: bot_handoff_conversation_ids_subquery)
  end

  def bot_handoffs
    events = scope.reporting_events.joins(:conversation).select(:conversation_id).where(
      account_id: account.id,
      name: :conversation_bot_handoff,
      created_at: range
    )

    visible_reporting_event_scope(events).distinct
  end

  def bot_handoff_conversation_ids_subquery
    bot_handoffs
  end

  def avg_first_response_time
    events = scope.reporting_events.where(name: 'first_response', account_id: account.id)
    grouped_reporting_events = get_grouped_values visible_reporting_event_scope(events)
    return grouped_reporting_events.average(:value_in_business_hours) if params[:business_hours]

    grouped_reporting_events.average(:value)
  end

  def reply_time
    events = scope.reporting_events.where(name: 'reply_time', account_id: account.id)
    grouped_reporting_events = get_grouped_values visible_reporting_event_scope(events)
    return grouped_reporting_events.average(:value_in_business_hours) if params[:business_hours]

    grouped_reporting_events.average(:value)
  end

  def avg_resolution_time
    events = scope.reporting_events.where(name: 'conversation_resolved', account_id: account.id)
    grouped_reporting_events = get_grouped_values visible_reporting_event_scope(events)
    return grouped_reporting_events.average(:value_in_business_hours) if params[:business_hours]

    grouped_reporting_events.average(:value)
  end

  def avg_resolution_time_summary
    reporting_events = scope.reporting_events
                            .where(name: 'conversation_resolved', account_id: account.id, created_at: range)
    reporting_events = visible_reporting_event_scope(reporting_events)
    avg_rt = if params[:business_hours].present?
               reporting_events.average(:value_in_business_hours)
             else
               reporting_events.average(:value)
             end

    return 0 if avg_rt.blank?

    avg_rt
  end

  def reply_time_summary
    reporting_events = scope.reporting_events
                            .where(name: 'reply_time', account_id: account.id, created_at: range)
    reporting_events = visible_reporting_event_scope(reporting_events)
    reply_time = params[:business_hours] ? reporting_events.average(:value_in_business_hours) : reporting_events.average(:value)

    return 0 if reply_time.blank?

    reply_time
  end

  def avg_first_response_time_summary
    reporting_events = scope.reporting_events
                            .where(name: 'first_response', account_id: account.id, created_at: range)
    reporting_events = visible_reporting_event_scope(reporting_events)
    avg_frt = if params[:business_hours].present?
                reporting_events.average(:value_in_business_hours)
              else
                reporting_events.average(:value)
              end

    return 0 if avg_frt.blank?

    avg_frt
  end

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
