class KanbanCards::VisibleBoardCardsQuery
  Result = Struct.new(:cards, :has_more, :next_cursor, :total_count, :groups, keyword_init: true)
  RefreshRequiredError = Class.new(StandardError)

  DEFAULT_LIMIT = 20
  MAX_LIMIT = 50
  GROUP_BY_VALUES = %w[stage assignee priority].freeze
  DEFAULT_GROUP_BY = 'stage'.freeze

  ASSIGNEE_ORDER_SQL = <<~SQL.squish.freeze
    COALESCE((
      SELECT MIN(LOWER(users.name))
      FROM kanban_card_assignees
      INNER JOIN users ON users.id = kanban_card_assignees.user_id
      WHERE kanban_card_assignees.kanban_card_id = kanban_cards.id
    ), '')
  SQL

  # The single assignee a card is grouped under: the same one ASSIGNEE_ORDER_SQL
  # sorts it by, so a card with several assignees lands in exactly one group.
  PRIMARY_ASSIGNEE_ID_SQL = <<~SQL.squish.freeze
    (SELECT kanban_card_assignees.user_id
     FROM kanban_card_assignees
     INNER JOIN users ON users.id = kanban_card_assignees.user_id
     WHERE kanban_card_assignees.kanban_card_id = kanban_cards.id
     ORDER BY LOWER(users.name) ASC, users.id ASC
     LIMIT 1)
  SQL

  # rubocop:disable Metrics/ParameterLists
  def initialize(account:, kanban_board:, visible_cards:, limit: DEFAULT_LIMIT, cursor: nil,
                 due_date_from: nil, due_date_to: nil, without_due_date: false, group_by: DEFAULT_GROUP_BY)
    @account = account
    @kanban_board = kanban_board
    @board_visible_cards = visible_cards
    @limit = limit
    @cursor = cursor
    @due_date_from = due_date_from
    @due_date_to = due_date_to
    @without_due_date = without_due_date
    @group_by = group_by
  end
  # rubocop:enable Metrics/ParameterLists

  def call
    return empty_result unless valid_board?

    anchor = cursor_after_id.present? ? cursor_anchor! : nil
    ids = paginated_card_ids(anchor)
    page_ids = ids.first(effective_limit)

    Result.new(
      cards: payload_cards(page_ids),
      has_more: ids.length > effective_limit,
      next_cursor: next_cursor_for(page_ids, ids),
      total_count: anchor.nil? ? visible_cards.count : nil,
      groups: anchor.nil? ? group_summaries : nil
    )
  end

  private

  attr_reader :account, :kanban_board, :limit, :cursor, :due_date_from, :due_date_to, :without_due_date, :group_by

  def empty_result
    Result.new(cards: [], has_more: false, next_cursor: nil, total_count: 0, groups: [])
  end

  def valid_board?
    kanban_board.account_id == account.id && kanban_board.active?
  end

  def visible_cards
    @visible_cards ||= begin
      scope = @board_visible_cards.joins(:kanban_stage).merge(KanbanStage.active)
      scope = scope.where(due_date_condition) if due_date_condition
      scope
    end
  end

  def due_date_condition
    return card_table[:due_at].eq(nil) if without_due_date

    conditions = []
    conditions << card_table[:due_at].gteq(due_date_from) if due_date_from.present?
    conditions << card_table[:due_at].lteq(due_date_to) if due_date_to.present?
    conditions.reduce(:and)
  end

  # Counting on every page would re-scan the funnel on each load-more click, so the
  # group headers read their count and value from the first page only. Stage groups
  # are left out: the board payload already carries a total per stage column.
  def group_summaries
    case group_by
    when 'assignee' then assignee_group_summaries
    when 'priority' then priority_group_summaries
    end
  end

  def assignee_group_summaries
    metrics = KanbanCards::Totals.grouped_metrics(visible_cards, PRIMARY_ASSIGNEE_ID_SQL)
    names = User.where(id: metrics.keys.compact).pluck(:id, :name).to_h

    metrics
      .map { |user_id, metric| group_summary(user_id&.to_s || 'unassigned', names[user_id], metric) }
      .sort_by { |group| [group[:name].present? ? 1 : 0, group[:name].to_s.downcase] }
  end

  def priority_group_summaries
    metrics = KanbanCards::Totals.metrics(visible_cards, priority_conditions)

    priority_conditions.keys.filter_map do |key|
      metric = metrics.fetch(key)
      group_summary(key, nil, metric) if metric.count.positive?
    end
  end

  # Ordered like COALESCE(priority, -1): the cards without one come first.
  def priority_conditions
    @priority_conditions ||= { 'none' => card_table[:priority].eq(nil) }.merge(
      KanbanCard.priorities.transform_values { |value| card_table[:priority].eq(value) }
    )
  end

  def group_summary(key, name, metric)
    { key: key, name: name, count: metric.count, total_value: KanbanCards::Totals.decimal_string(metric.value) }
  end

  def paginated_card_ids(anchor)
    scope = visible_cards
    scope = scope.where(after_anchor_condition(anchor)) if anchor.present?
    scope.order(Arel.sql(order_sql)).limit(effective_limit + 1).ids
  end

  def order_sql
    order_expressions.join(', ')
  end

  def order_expressions
    case group_by
    when 'assignee'
      ["#{ASSIGNEE_ORDER_SQL} ASC", *stage_and_card_order]
    when 'priority'
      ['COALESCE(kanban_cards.priority, -1) ASC', *stage_and_card_order]
    else
      stage_and_card_order
    end
  end

  def stage_and_card_order
    [
      'kanban_stages.position ASC', 'kanban_stages.created_at ASC', 'kanban_stages.id ASC',
      'kanban_cards.position ASC', 'kanban_cards.created_at ASC', 'kanban_cards.id ASC'
    ]
  end

  def after_anchor_condition(anchor)
    values = stage_and_card_anchor_values(anchor)
    expressions = stage_and_card_order.map { |expression| expression.delete_suffix(' ASC') }

    case group_by
    when 'assignee'
      expressions.unshift(ASSIGNEE_ORDER_SQL)
      values.unshift(anchor_assignee_name(anchor))
    when 'priority'
      expressions.unshift('COALESCE(kanban_cards.priority, -1)')
      values.unshift(KanbanCard.priorities.fetch(anchor.priority, -1))
    end

    ["(#{expressions.join(', ')}) > (#{(['?'] * values.length).join(', ')})", *values]
  end

  def stage_and_card_anchor_values(anchor)
    stage = anchor.kanban_stage
    [stage.position, stage.created_at, stage.id, anchor.position, anchor.created_at, anchor.id]
  end

  def anchor_assignee_name(anchor)
    anchor.assignees.minimum(Arel.sql('LOWER(users.name)')) || ''
  end

  def payload_cards(ids)
    KanbanCards::CompactCardsQuery.call(ids)
  end

  def cursor_anchor!
    visible_cards.find_by(id: cursor_after_id) || raise(RefreshRequiredError, 'Kanban cards cursor is no longer valid')
  end

  def next_cursor_for(page_ids, ids)
    return if ids.length <= effective_limit || page_ids.blank?

    { after_id: page_ids.last }
  end

  def effective_limit
    @effective_limit ||= (limit || DEFAULT_LIMIT).to_i
  end

  def cursor_after_id
    return if cursor.blank?

    cursor[:after_id] || cursor['after_id']
  end

  def card_table
    KanbanCard.arel_table
  end
end
