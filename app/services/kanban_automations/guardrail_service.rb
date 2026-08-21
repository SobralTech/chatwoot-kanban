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
    reason = blocking_reason
    reason ? blocked(reason) : allowed
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

  # Ordered cheapest first, and each check stops the chain: the query-backed ones below
  # are never reached once something above them has already blocked the send.
  def blocking_reason
    free_reason || queried_reason
  end

  def free_reason
    return 'global_kill_switch' unless self.class.global_enabled?
    return 'board_kill_switch' unless self.class.board_enabled?(board)
    return 'card_without_conversation' if conversation.blank?
    return 'outside_business_hours' unless within_business_hours?

    nil
  end

  def queried_reason
    return 'conversation_resolved' if resolved_without_permission?
    return 'max_auto_messages_per_contact' if max_auto_messages_reached?
    return 'human_silence' if human_spoke_recently?
    return 'customer_replied' if customer_replied_after_trigger?

    nil
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
                .where("COALESCE(additional_attributes ->> 'campaign_id', '') = ''")
                .pluck(:content_attributes)
                .any? { |attributes| attributes.to_h['automation_rule_id'].blank? }
  end

  # messages.content_attributes is a json column that holds a JSON *string*, so
  # `content_attributes ->> 'key'` reads nothing and this predicate cannot move into
  # SQL. Plucking the one column at least avoids instantiating every message.
  def automated_messages_count
    Message.joins(:conversation)
           .where(conversations: { account_id: account.id, contact_id: card.contact_id })
           .where(message_type: :outgoing, private: false)
           .where('messages.created_at >= ?', 24.hours.ago)
           .pluck(:content_attributes)
           .count { |attributes| attributes.to_h['automation_rule_id'].present? }
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
