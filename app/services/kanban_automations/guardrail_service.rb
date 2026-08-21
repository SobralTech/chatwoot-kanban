class KanbanAutomations::GuardrailService
  DEFAULT_BUSINESS_HOURS = {
    start: '08:00',
    end: '18:00',
    days: [1, 2, 3, 4, 5, 6]
  }.freeze
  DEFAULT_SETTINGS = {
    business_hours: DEFAULT_BUSINESS_HOURS,
    max_auto_messages_per_contact_per_day: 2,
    human_silence_minutes: 30,
    enabled: true
  }.freeze

  Result = Struct.new(:allowed, :reason, :metadata, keyword_init: true) do
    def allowed?
      allowed
    end
  end

  def self.check(card:, rule:, action_params:, context: {})
    new(card: card, rule: rule, action_params: action_params, context: context).check
  end

  def self.automations_enabled?(card)
    global_enabled? && board_enabled?(card&.kanban_board)
  end

  def self.global_enabled?
    ActiveModel::Type::Boolean.new.cast(
      GlobalConfigService.load('KANBAN_AUTOMATIONS_ENABLED', 'true')
    )
  end

  def self.board_enabled?(board)
    return false if board.blank?

    settings = board.automation_settings.to_h.with_indifferent_access
    ActiveModel::Type::Boolean.new.cast(settings.fetch(:enabled, true))
  end

  def initialize(card:, rule:, action_params:, context: {})
    @card = card
    @rule = rule
    @action_params = action_params.to_h.with_indifferent_access
    @context = context.to_h.with_indifferent_access
  end

  def check
    reason = guardrail_reasons.find(&:present?)
    return blocked(reason) if reason

    allowed
  end

  private

  attr_reader :card, :rule, :action_params, :context

  def account
    card.account
  end

  def board
    card.kanban_board
  end

  def conversation
    card.conversation
  end

  def settings
    @settings ||= DEFAULT_SETTINGS.deep_merge(board.automation_settings.to_h.with_indifferent_access)
  end

  def within_business_hours?
    local_time = local_account_time
    return false unless business_days.include?(local_time.wday)

    current_minutes = (local_time.hour * 60) + local_time.min
    start_minutes = time_in_minutes(business_hours[:start], 8 * 60)
    end_minutes = time_in_minutes(business_hours[:end], 18 * 60)

    current_minutes >= start_minutes && current_minutes < end_minutes
  end

  def guardrail_reasons
    return ['global_kill_switch'] unless self.class.global_enabled?
    return ['board_kill_switch'] unless self.class.board_enabled?(board)
    return ['card_without_conversation'] if conversation.blank?

    [
      business_hours_reason,
      message_limit_reason,
      human_silence_reason,
      customer_response_reason,
      resolved_conversation_reason
    ]
  end

  def business_hours_reason
    'outside_business_hours' unless within_business_hours?
  end

  def message_limit_reason
    'max_auto_messages_per_contact' if max_auto_messages_reached?
  end

  def human_silence_reason
    'human_silence' if human_spoke_recently?
  end

  def customer_response_reason
    'customer_replied' if customer_replied_after_trigger?
  end

  def resolved_conversation_reason
    'conversation_resolved' if resolved_without_permission?
  end

  def local_account_time
    Time.current.in_time_zone(account_timezone)
  end

  def business_hours
    settings[:business_hours].to_h.with_indifferent_access
  end

  def business_days
    days = Array(business_hours[:days]).presence || DEFAULT_BUSINESS_HOURS[:days]
    days.filter_map { |day| Integer(day, exception: false) }
  end

  def max_auto_messages_reached?
    limit = settings[:max_auto_messages_per_contact_per_day].to_i
    return false if limit.negative?

    automated_messages_count >= limit
  end

  def human_spoke_recently?
    silence_minutes = settings[:human_silence_minutes].to_i
    return false if silence_minutes.negative?

    conversation.messages.outgoing
                .where(private: false, sender_type: 'User')
                .where('messages.created_at >= ?', silence_minutes.minutes.ago)
                .to_a
                .any? { |message| human_message?(message) }
  end

  def automated_messages_count
    Message.joins(:conversation)
           .where(conversations: { account_id: account.id, contact_id: card.contact_id })
           .where(message_type: :outgoing, private: false)
           .where('messages.created_at >= ?', 24.hours.ago)
           .to_a
           .count { |message| message.content_attributes['automation_rule_id'].present? }
  end

  def human_message?(message)
    message.content_attributes['automation_rule_id'].blank? &&
      message.additional_attributes['campaign_id'].blank?
  end

  def customer_replied_after_trigger?
    conversation.messages.incoming
                .where(private: false)
                .exists?(['messages.created_at > ?', triggered_at])
  end

  def resolved_without_permission?
    conversation.resolved? && !ActiveModel::Type::Boolean.new.cast(action_params[:allow_resolved])
  end

  def triggered_at
    value = context[:triggered_at]
    return Time.current if value.blank?

    value.respond_to?(:to_time) ? value.to_time : Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    Time.current
  end

  def account_timezone
    timezone = account.reporting_timezone.presence || card.inbox&.timezone.presence || Time.zone.name
    ActiveSupport::TimeZone[timezone] || Time.zone
  end

  def time_in_minutes(value, fallback)
    hour, minute = value.to_s.split(':', 2).map(&:to_i)
    return fallback unless hour.between?(0, 23) && minute.between?(0, 59)

    (hour * 60) + minute
  end

  def allowed
    Result.new(allowed: true, reason: nil, metadata: {})
  end

  def blocked(reason)
    Result.new(allowed: false, reason: reason, metadata: { reason: reason })
  end
end
