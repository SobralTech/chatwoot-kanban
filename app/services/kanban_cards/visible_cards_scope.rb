class KanbanCards::VisibleCardsScope
  MATCH_MODES = %w[all any].freeze
  # The controllers fall back to this when the request omits match_mode; a nil match_mode
  # reaching this class still means "all", so every filter category has to match.
  DEFAULT_MATCH_MODE = 'any'.freeze

  # rubocop:disable Metrics/ParameterLists
  def initialize(account:, user:, kanban_board:, account_user: nil,
                 filtered_inbox_ids: nil, filtered_assignee_ids: nil, filtered_card_statuses: nil,
                 filtered_priorities: nil, filtered_due_dates: nil, filtered_created_dates: nil, filtered_labels: nil,
                 match_mode: nil, search_query: nil)
    @account = account
    @user = user
    @kanban_board = kanban_board
    @account_user = account_user
    @filtered_inbox_ids = normalized_filter(filtered_inbox_ids)
    @filtered_assignee_ids = normalized_filter(filtered_assignee_ids)
    @filtered_card_statuses = normalized_filter(filtered_card_statuses)
    @filtered_priorities = normalized_filter(filtered_priorities)
    @filtered_due_dates = normalized_filter(filtered_due_dates)
    @filtered_created_dates = normalized_filter(filtered_created_dates)
    @filtered_labels = normalized_filter(filtered_labels)
    @match_mode = match_mode
    @search_query = search_query
  end
  # rubocop:enable Metrics/ParameterLists

  def call
    scope = KanbanCard
            .active
            .left_outer_joins(:conversation, :contact)
            .where(account_id: account.id, kanban_board_id: kanban_board.id)
            .where(visibility_condition)
    scope = scope.where(combined_filter_condition) if combined_filter_condition
    scope = scope.where(search_condition) if search_query.present?
    scope
  end

  private

  attr_reader :account, :user, :kanban_board,
              :filtered_inbox_ids, :filtered_assignee_ids, :filtered_card_statuses,
              :filtered_priorities, :filtered_due_dates, :filtered_created_dates, :filtered_labels, :match_mode, :search_query

  def visibility_condition
    KanbanCards::VisibilityCondition.new(account: account, user: user, account_user: @account_user).call
  end

  def search_condition
    KanbanCards::SearchCondition.new(search_query: search_query).call
  end

  def normalized_filter(values)
    values.nil? ? nil : Array(values).uniq
  end

  def combined_filter_condition
    return if filter_conditions.blank?

    filter_conditions.reduce(match_any? ? :or : :and)
  end

  def filter_conditions
    [
      inbox_condition,
      assignee_condition,
      card_status_condition,
      priority_condition,
      due_date_condition,
      created_date_condition,
      label_condition
    ].compact
  end

  def inbox_condition
    card_table[:inbox_id].in(filtered_inbox_ids) unless filtered_inbox_ids.nil?
  end

  # Cards carry their own assignees (and render them); the conversation assignee is a
  # different, single-valued thing that manual cards do not have at all.
  def assignee_condition
    card_table[:id].in(card_ids_with_assignees) if filtered_assignee_ids.present?
  end

  def card_ids_with_assignees
    KanbanCardAssignee.where(user_id: filtered_assignee_ids).select(:kanban_card_id).arel
  end

  def card_status_condition
    return if filtered_card_statuses.blank?

    conditions = filtered_card_statuses.filter_map do |status|
      case status
      when 'open'
        open_card_condition
      when 'won'
        card_status_stage_condition(kanban_board.won_stage_id)
      when 'lost'
        card_status_stage_condition(kanban_board.lost_stage_id)
      end
    end
    or_condition(conditions)
  end

  # An empty special-stage list compiles to `1=1`, so every card counts as open.
  def open_card_condition
    card_table[:kanban_stage_id].not_in(KanbanStage.special_stage_ids(kanban_board))
  end

  def card_status_stage_condition(stage_id)
    return card_table[:id].eq(nil) if stage_id.blank?

    card_table[:kanban_stage_id].eq(stage_id)
  end

  def priority_condition
    return if filtered_priorities.blank?

    conditions = []
    priority_values = filtered_priorities.filter_map { |priority| KanbanCard.priorities[priority] }
    conditions << card_table[:priority].in(priority_values) if priority_values.present?
    conditions << card_table[:priority].eq(nil) if filtered_priorities.include?('none')
    or_condition(conditions)
  end

  def due_date_condition
    return if filtered_due_dates.blank?

    conditions = filtered_due_dates.filter_map do |due_date|
      due_date_bucket_condition(due_date)
    end
    or_condition(conditions)
  end

  def due_date_bucket_condition(due_date)
    return card_table[:due_at].eq(nil) if due_date == 'none'
    return card_table[:due_at].lt(Time.current) if due_date == 'overdue'

    due_date_window_condition(due_date)
  end

  def due_date_window_condition(due_date)
    duration = { 'day' => 1.day, 'week' => 1.week, 'month' => 1.month }[due_date]
    return unless duration

    now = Time.current
    card_table[:due_at].gteq(now).and(card_table[:due_at].lteq(now + duration))
  end

  def created_date_condition
    return if filtered_created_dates.blank?

    conditions = filtered_created_dates.filter_map do |created_date|
      created_date_window_condition(created_date)
    end
    or_condition(conditions)
  end

  # Unlike due_at, created_at always looks backward from now: a "week" bucket means
  # created within the last week, not the next one.
  def created_date_window_condition(created_date)
    duration = { 'day' => 1.day, 'week' => 1.week, 'month' => 1.month }[created_date]
    return unless duration

    now = Time.current
    card_table[:created_at].gteq(now - duration).and(card_table[:created_at].lteq(now))
  end

  def label_condition
    return if filtered_labels.blank?

    conditions = []
    label_names = filtered_labels - ['none']
    conditions << card_table[:id].in(card_ids_with_labels(label_names)) if label_names.present?
    conditions << card_table[:id].not_in(card_ids_with_labels) if filtered_labels.include?('none')
    or_condition(conditions)
  end

  def card_ids_with_labels(label_names = nil)
    taggings = ActsAsTaggableOn::Tagging.where(taggable_type: 'KanbanCard', context: 'labels')
    taggings = taggings.joins(:tag).where(tags: { name: label_names }) if label_names.present?
    taggings.select(:taggable_id).arel
  end

  def match_any?
    match_mode == 'any'
  end

  def or_condition(conditions)
    conditions.reduce { |condition, next_condition| condition.or(next_condition) }
  end

  def card_table
    KanbanCard.arel_table
  end
end
