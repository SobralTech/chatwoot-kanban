class KanbanReports::BaseQuery
  GROUP_BY_VALUES = %w[day week].freeze
  STAGE_EVENT_TYPES = %w[card_created stage_changed board_changed reopened won lost].freeze
  TERMINAL_EVENT_TYPES = %w[won lost].freeze

  # rubocop:disable Metrics/ParameterLists
  def initialize(account:, kanban_board:, user: nil, current_user: nil, since: nil, until: nil, group_by: 'day',
                 timezone_offset: nil, business_hours: false, agent_ids: [], inbox_ids: [], labels: [])
    @account = account
    @kanban_board = kanban_board
    @user = user || current_user
    @since = parse_time(since) || 30.days.ago
    # `until` is a Ruby keyword, so its keyword argument is read by name.
    until_value = binding.local_variable_get(:until)
    @until = parse_time(until_value) || Time.current
    @since, @until = @until, @since if @since > @until
    @group_by = group_by.presence || 'day'
    @timezone_offset = timezone_offset
    @business_hours = business_hours
    @agent_ids = normalized_ids(agent_ids)
    @inbox_ids = normalized_ids(inbox_ids)
    @labels = normalized_values(labels)
    validate_group_by!
  end
  # rubocop:enable Metrics/ParameterLists

  protected

  attr_reader :account, :kanban_board, :user, :since, :until, :group_by, :business_hours,
              :timezone_offset, :agent_ids, :inbox_ids, :labels

  def filtered_cards
    @filtered_cards ||= begin
      scope = KanbanCards::VisibleCardsScope.new(
        account: account,
        user: user,
        account_user: account_user,
        kanban_board: kanban_board
      ).call

      scope = scope.where(inbox_id: inbox_ids) if inbox_ids.present?
      scope = scope.where(id: cards_for_agents) if agent_ids.present?
      scope = scope.where(id: cards_for_labels) if labels.present?
      scope
    end
  end

  def period_events(types: STAGE_EVENT_TYPES, range: since..self.until)
    scope = KanbanCardEvent
            .where(account_id: account.id, kanban_board_id: kanban_board.id)
            .where(kanban_card_id: filtered_cards.select(:id))
            .where(event_type: types)
    scope.where(created_at: range).order(:kanban_card_id, :created_at, :id)
  end

  def events_until_cutoff
    period_events(range: ..self.until)
  end

  def unique_terminal_events
    unique_events_by_card(period_events(types: TERMINAL_EVENT_TYPES), &:event_type)
  end

  def unique_events_by_card(events)
    seen = {}
    events.each_with_object([]) do |event, result|
      key = [event.kanban_card_id, yield(event)]
      next if seen[key]

      seen[key] = true
      result << event
    end
  end

  def stage_entry(event)
    metadata = event.metadata || {}
    stage_id = case event.event_type
               when 'card_created', 'won', 'lost'
                 metadata['stage_id']
               when 'stage_changed', 'board_changed', 'reopened'
                 metadata['to_stage_id']
               end
    stage_id.presence&.to_i
  end

  def stages
    @stages ||= kanban_board.kanban_stages.active.ordered.to_a
  end

  def period_bucket(time)
    local_time = time.in_time_zone(report_timezone)
    return local_time.beginning_of_week(:monday) if group_by == 'week'

    local_time.beginning_of_day
  end

  def report_timezone
    @report_timezone ||= begin
      offset = timezone_offset.to_f if timezone_offset.present?
      ActiveSupport::TimeZone[offset] if offset
    end || ActiveSupport::TimeZone[account.reporting_timezone.presence || Time.zone.name] || Time.zone
  end

  def bucket_label(bucket)
    bucket.to_date.iso8601
  end

  def percentage(value, total)
    return 0.0 if total.to_f.zero?

    (value.to_f * 100 / total).round(2)
  end

  def metric_payload(metric)
    {
      count: metric.count,
      value: KanbanCards::Totals.decimal_string(metric.value)
    }
  end

  def metric_for(card_ids)
    metric_for_scope(filtered_cards.where(id: card_ids))
  end

  def metric_for_scope(scope)
    return KanbanCards::Totals::Metric.new(0, BigDecimal(0)) unless scope.exists?

    KanbanCards::Totals.metric(scope)
  end

  def card_ids_for_events(events)
    events.map(&:kanban_card_id).uniq
  end

  def account_user
    @account_user ||= account.account_users.find_by(user_id: user&.id)
  end

  def cards_for_agents
    KanbanCardAssignee
      .where(account_id: account.id, user_id: agent_ids)
      .select(:kanban_card_id)
  end

  def cards_for_labels
    return KanbanCard.where(id: []) if labels == ['none']

    label_names = labels - ['none']
    tagged_cards = ActsAsTaggableOn::Tagging
                   .where(taggable_type: 'KanbanCard', context: 'labels')
                   .joins(:tag)
    matching_cards = tagged_cards.where(tags: { name: label_names }).select(:taggable_id)
    return matching_cards if labels.exclude?('none')

    all_tagged_cards = tagged_cards.select(:taggable_id)
    KanbanCard.where(id: matching_cards).or(KanbanCard.where.not(id: all_tagged_cards)).select(:id)
  end

  def parse_time(value)
    return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)
    return if value.blank?
    return Time.zone.at(value.to_f) if value.to_s.match?(/\A-?\d+(?:\.\d+)?\z/)

    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def normalized_ids(values)
    Array(values).flat_map { |value| value.to_s.split(',') }.filter_map(&:presence).map(&:to_i).uniq
  end

  def normalized_values(values)
    Array(values).flat_map { |value| value.to_s.split(',') }.filter_map(&:presence).map(&:to_s).uniq
  end

  def validate_group_by!
    return if GROUP_BY_VALUES.include?(group_by)

    raise ArgumentError, 'invalid group_by'
  end
end
