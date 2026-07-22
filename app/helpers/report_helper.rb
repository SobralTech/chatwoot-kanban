module ReportHelper
  include ReportVisibilityHelper

  private

  def scope
    scope_method = { account: :account, inbox: :inbox, agent: :user, label: :label, team: :team }[params[:type]]

    send(scope_method) if scope_method
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

    visible_reporting_event_scope(events).where.not(conversation_id: bot_handoffs)
  end

  def bot_handoffs
    events = scope.reporting_events.joins(:conversation).select(:conversation_id).where(
      account_id: account.id,
      name: :conversation_bot_handoff,
      created_at: range
    )

    visible_reporting_event_scope(events).distinct
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
end
