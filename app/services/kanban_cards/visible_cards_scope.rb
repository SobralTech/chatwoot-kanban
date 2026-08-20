# rubocop:disable Metrics/ClassLength
class KanbanCards::VisibleCardsScope
  # rubocop:disable Metrics/ParameterLists
  def initialize(account:, user:, kanban_board:, visible_inbox_ids: nil, visible_team_ids: nil, account_user: nil,
                 filtered_inbox_ids: nil, filtered_assignee_ids: nil, filtered_card_statuses: nil,
                 filtered_priorities: nil, filtered_due_dates: nil, filtered_labels: nil, match_mode: nil,
                 search_query: nil)
    @account = account
    @user = user
    @kanban_board = kanban_board
    @visible_inbox_ids = visible_inbox_ids
    @visible_team_ids = visible_team_ids
    @account_user = account_user
    @filtered_inbox_ids = normalized_filter(filtered_inbox_ids)
    @filtered_assignee_ids = normalized_filter(filtered_assignee_ids)
    @filtered_card_statuses = normalized_filter(filtered_card_statuses)
    @filtered_priorities = normalized_filter(filtered_priorities)
    @filtered_due_dates = normalized_filter(filtered_due_dates)
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
              :filtered_priorities, :filtered_due_dates, :filtered_labels, :match_mode, :search_query

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
      label_condition
    ].compact
  end

  def inbox_condition
    card_table[:inbox_id].in(filtered_inbox_ids) if filtered_inbox_ids.present?
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

  def open_card_condition
    special_stage_ids = KanbanStage.special_stage_ids(kanban_board)
    return card_table[:id].not_eq(nil) if special_stage_ids.blank?

    card_table[:kanban_stage_id].not_in(special_stage_ids)
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

  def search_condition
    search_tokens
      .map { |token| token_condition(token) }
      .reduce(:and)
  end

  def search_tokens
    search_query.to_s.split(/\s+/).first(5).map do |token|
      ActiveSupport::Inflector.transliterate(token).downcase
    end
  end

  def token_condition(token)
    conditions = [
      card_table[:id].in(subject_ids_matching(token)),
      contact_id_matching(token)
    ]
    conditions.reduce(:or)
  end

  def subject_ids_matching(token)
    KanbanCard
      .active
      .where(unaccented_like(KanbanCard.arel_table[:subject], token))
      .select(:id)
      .arel
  end

  def contact_id_matching(token)
    card_table[:contact_id].in(contact_ids_matching(token))
  end

  def contact_ids_matching(token)
    Contact
      .where(contact_token_condition(token))
      .select(:id)
      .arel
  end

  def contact_token_condition(token)
    conditions = [
      unaccented_like(contact_table[:name], token),
      plain_like(contact_table[:email], token)
    ]
    conditions << phone_like(token) if token.match?(/\d/)
    conditions.reduce(:or)
  end

  def unaccented_like(column, token)
    named_function('immutable_unaccent', named_function('lower', column)).matches(bind_param(like_pattern(token)))
  end

  def plain_like(column, token)
    named_function('lower', column).matches(bind_param(like_pattern(token)))
  end

  def phone_like(token)
    named_function(
      'regexp_replace',
      contact_table[:phone_number],
      Arel::Nodes.build_quoted('\\D'),
      Arel::Nodes.build_quoted(''),
      Arel::Nodes.build_quoted('g')
    ).matches(bind_param(like_pattern(token.gsub(/\D/, ''))))
  end

  def like_pattern(token)
    "%#{ActiveRecord::Base.sanitize_sql_like(token)}%"
  end

  def named_function(name, *expressions)
    Arel::Nodes::NamedFunction.new(name, expressions)
  end

  def bind_param(value)
    Arel::Nodes::BindParam.new(value)
  end

  def visibility_condition
    return manual_card_condition.or(valid_conversation_card_condition) if administrator?
    return valid_conversation_card_condition if user.is_a?(AgentBot)

    agent_visibility_condition
  end

  def agent_visibility_condition
    conditions = []
    conditions << accessible_manual_card_condition if visible_inbox_ids.present?
    conditions << accessible_conversation_card_condition if conversation_access_condition

    or_condition(conditions) || card_table[:id].eq(nil)
  end

  def accessible_manual_card_condition
    manual_card_condition.and(card_table[:inbox_id].in(visible_inbox_ids))
  end

  def accessible_conversation_card_condition
    valid_conversation_card_condition.and(conversation_access_condition)
  end

  def conversation_access_condition
    @conversation_access_condition ||= or_condition(conversation_access_conditions)
  end

  def conversation_access_conditions
    conditions = []
    conditions << conversation_table[:inbox_id].in(visible_inbox_ids) if visible_inbox_ids.present?
    conditions << conversation_table[:team_id].in(visible_team_ids) if visible_team_ids.present?
    conditions
  end

  def valid_conversation_card_condition
    condition = card_table[:conversation_id].not_eq(nil)
    condition = condition.and(conversation_table[:account_id].eq(account.id))
    condition = condition.and(conversation_table[:contact_id].eq(card_table[:contact_id]))
    condition.and(conversation_table[:inbox_id].eq(card_table[:inbox_id]))
  end

  def manual_card_condition
    card_table[:conversation_id].eq(nil)
  end

  def or_condition(conditions)
    conditions.reduce { |condition, next_condition| condition.or(next_condition) }
  end

  def visible_inbox_ids
    @visible_inbox_ids ||= user.inboxes.where(account_id: account.id).pluck(:id)
  end

  def visible_team_ids
    @visible_team_ids ||= user.teams.where(account_id: account.id).pluck(:id)
  end

  def administrator?
    account_user&.administrator?
  end

  def account_user
    return unless user.respond_to?(:account_users)

    @account_user ||= user.account_users.find_by(account: account)
  end

  def card_table
    KanbanCard.arel_table
  end

  def conversation_table
    Conversation.arel_table
  end

  def contact_table
    Contact.arel_table
  end
end
# rubocop:enable Metrics/ClassLength
