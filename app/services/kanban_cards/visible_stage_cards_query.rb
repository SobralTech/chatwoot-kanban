class KanbanCards::VisibleStageCardsQuery
  Result = Struct.new(:cards, :has_more, :next_cursor, :total_count, :total_value, keyword_init: true)
  RefreshRequiredError = Class.new(StandardError)

  DEFAULT_LIMIT = 20
  MAX_LIMIT = 50
  MATCH_MODES = %w[all any].freeze
  DEFAULT_MATCH_MODE = 'any'.freeze
  TERMINAL_PERIODS = { '7d' => 7, '30d' => 30, '90d' => 90 }.freeze
  ALL_TIME_TERMINAL_PERIOD = 'all'.freeze
  TERMINAL_PERIOD_VALUES = (TERMINAL_PERIODS.keys + [ALL_TIME_TERMINAL_PERIOD]).freeze
  DEFAULT_TERMINAL_PERIOD = '30d'.freeze

  # rubocop:disable Metrics/ParameterLists
  # rubocop:disable Metrics/MethodLength
  def initialize(account:, user:, kanban_board:, kanban_stage:, limit: DEFAULT_LIMIT, cursor: nil, visible_inbox_ids: nil,
                 visible_team_ids: nil, account_user: nil, filtered_inbox_ids: nil, filtered_assignee_ids: nil,
                 filtered_card_statuses: nil, filtered_priorities: nil, filtered_due_dates: nil, filtered_labels: nil,
                 match_mode: DEFAULT_MATCH_MODE, search_query: nil, terminal_period: DEFAULT_TERMINAL_PERIOD)
    @account = account
    @user = user
    @kanban_board = kanban_board
    @kanban_stage = kanban_stage
    @limit = limit
    @cursor = cursor
    @visible_cards_scope = KanbanCards::VisibleCardsScope.new(
      account: account,
      user: user,
      kanban_board: kanban_board,
      visible_inbox_ids: visible_inbox_ids,
      visible_team_ids: visible_team_ids,
      account_user: account_user,
      filtered_inbox_ids: filtered_inbox_ids,
      filtered_assignee_ids: filtered_assignee_ids,
      filtered_card_statuses: filtered_card_statuses,
      filtered_priorities: filtered_priorities,
      filtered_due_dates: filtered_due_dates,
      filtered_labels: filtered_labels,
      match_mode: match_mode,
      search_query: search_query
    )
    @terminal_period = terminal_period.presence || DEFAULT_TERMINAL_PERIOD
  end
  # rubocop:enable Metrics/MethodLength
  # rubocop:enable Metrics/ParameterLists

  def call(load_cards: true)
    return empty_result unless valid_board_and_stage?

    return metadata_result unless load_cards

    anchor = cursor_after_id.present? ? cursor_anchor! : nil
    ids = paginated_card_ids(anchor)
    page_ids = ids.first(effective_limit)
    cards = payload_cards(page_ids)
    totals = anchor.nil? ? visible_totals : [nil, nil]

    Result.new(
      cards: cards,
      has_more: ids.length > effective_limit,
      next_cursor: next_cursor_for(page_ids, ids),
      # Counting on every cursor-paginated page would re-scan the whole
      # stage on each load-more click; only the first page needs it.
      total_count: totals.first,
      total_value: totals.last
    )
  end

  private

  attr_reader :account, :user, :kanban_board, :kanban_stage, :limit, :cursor, :terminal_period

  def empty_result
    Result.new(cards: [], has_more: false, next_cursor: nil, total_count: 0, total_value: 0)
  end

  def valid_board_and_stage?
    kanban_board.account_id == account.id &&
      kanban_board.active? &&
      kanban_stage.account_id == account.id &&
      kanban_stage.kanban_board_id == kanban_board.id &&
      kanban_stage.active?
  end

  def visible_cards
    @visible_cards ||= begin
      scope = @visible_cards_scope.call.where(kanban_stage_id: kanban_stage.id)
      # The period is a column slice, not a user filter, so it stays outside match_mode.
      scope = scope.where(terminal_period_condition) if terminal_period_condition
      scope
    end
  end

  def terminal_period_condition
    return unless terminal_stage?

    days = TERMINAL_PERIODS[terminal_period]
    return if days.blank? # 'all' keeps the whole history

    card_table[:stage_entered_at].gteq(days.days.ago)
  end

  def terminal_stage?
    KanbanStage.special_stage_ids(kanban_board).include?(kanban_stage.id)
  end

  def visible_totals
    @visible_totals ||= visible_cards
                        .left_outer_joins(:kanban_card_products)
                        .pick(card_table[:id].count(true), total_value_expression)
  end

  def metadata_result
    total_count, total_value = visible_totals

    Result.new(
      cards: [],
      has_more: false,
      next_cursor: nil,
      total_count: total_count,
      total_value: total_value
    )
  end

  def total_value_expression
    named_function(
      'COALESCE',
      named_function(
        'SUM',
        kanban_card_product_table[:unit_price] * kanban_card_product_table[:quantity]
      ),
      Arel::Nodes.build_quoted(0)
    )
  end

  def named_function(name, *expressions)
    Arel::Nodes::NamedFunction.new(name, expressions)
  end

  def paginated_card_ids(anchor)
    scope = visible_cards.ordered
    scope = scope.where(after_anchor_condition(anchor)) if anchor.present?

    scope.limit(effective_limit + 1).ids
  end

  def payload_cards(ids)
    return [] if ids.blank?

    cards_by_id = KanbanCard
                  .where(id: ids)
                  .includes(
                    conversation: { assignee: { avatar_attachment: :blob } },
                    contact: { avatar_attachment: :blob },
                    inbox: [:channel, { avatar_attachment: :blob }],
                    labels: [],
                    kanban_card_field_values: :kanban_custom_field
                  ).index_by(&:id)

    ids.filter_map { |id| cards_by_id[id] }
  end

  def cursor_anchor!
    visible_cards.find_by(id: cursor_after_id) || raise(RefreshRequiredError, 'Kanban cards cursor is no longer valid')
  end

  def after_anchor_condition(anchor)
    after_anchor_position(anchor)
      .or(after_anchor_created_at(anchor))
      .or(after_anchor_id(anchor))
  end

  def after_anchor_position(anchor)
    card_table[:position].gt(anchor.position)
  end

  def after_anchor_created_at(anchor)
    card_table[:position].eq(anchor.position).and(card_table[:created_at].gt(anchor.created_at))
  end

  def after_anchor_id(anchor)
    card_table[:position]
      .eq(anchor.position)
      .and(card_table[:created_at].eq(anchor.created_at))
      .and(card_table[:id].gt(anchor.id))
  end

  def next_cursor_for(page_ids, ids)
    return if ids.length <= effective_limit || page_ids.blank?

    { after_id: page_ids.last }
  end

  # Callers (controllers) are responsible for clamping limit to [1, MAX_LIMIT]
  # before it reaches this service.
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

  def kanban_card_product_table
    KanbanCardProduct.arel_table
  end
end
