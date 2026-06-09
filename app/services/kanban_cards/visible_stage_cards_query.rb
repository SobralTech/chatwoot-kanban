class KanbanCards::VisibleStageCardsQuery
  Result = Struct.new(:cards, :has_more, :next_cursor, :total_count, keyword_init: true)
  RefreshRequiredError = Class.new(StandardError)

  DEFAULT_LIMIT = 20
  MAX_LIMIT = 50

  # rubocop:disable Metrics/ParameterLists
  def initialize(account:, user:, kanban_board:, kanban_stage:, limit: DEFAULT_LIMIT, cursor: nil, visible_inbox_ids: nil,
                 visible_team_ids: nil, account_user: nil, filtered_inbox_ids: nil, filtered_assignee_ids: nil)
    @account = account
    @user = user
    @kanban_board = kanban_board
    @kanban_stage = kanban_stage
    @limit = limit
    @cursor = cursor
    @visible_inbox_ids = visible_inbox_ids
    @visible_team_ids = visible_team_ids
    @account_user = account_user
    @filtered_inbox_ids =
      filtered_inbox_ids.nil? ? nil : Array(filtered_inbox_ids).uniq
    @filtered_assignee_ids =
      filtered_assignee_ids.nil? ? nil : Array(filtered_assignee_ids).uniq
  end
  # rubocop:enable Metrics/ParameterLists

  def call
    return empty_result unless valid_board_and_stage?

    anchor = cursor_after_id.present? ? cursor_anchor! : nil
    total_count = visible_cards.count
    ids = paginated_card_ids(anchor)
    page_ids = ids.first(clamped_limit)
    cards = payload_cards(page_ids)

    Result.new(
      cards: cards,
      has_more: ids.length > clamped_limit,
      next_cursor: next_cursor_for(page_ids, ids),
      total_count: total_count
    )
  end

  private

  attr_reader :account, :user, :kanban_board, :kanban_stage, :limit, :cursor,
              :filtered_inbox_ids, :filtered_assignee_ids

  def empty_result
    Result.new(cards: [], has_more: false, next_cursor: nil, total_count: 0)
  end

  def valid_board_and_stage?
    kanban_board.account_id == account.id &&
      kanban_board.active? &&
      kanban_stage.account_id == account.id &&
      kanban_stage.kanban_board_id == kanban_board.id &&
      kanban_stage.active?
  end

  def visible_cards
    @visible_cards ||= KanbanCard
                       .active
                       .left_outer_joins(:conversation)
                       .where(account_id: account.id, kanban_board_id: kanban_board.id, kanban_stage_id: kanban_stage.id)
                       .where(visibility_condition)
                       .then { |scope| filtered_inbox_ids.nil? ? scope : scope.where(inbox_id: filtered_inbox_ids) }
                       .then { |scope| filtered_assignee_ids.nil? ? scope : scope.where(conversations: { assignee_id: filtered_assignee_ids }) }
  end

  def paginated_card_ids(anchor)
    scope = visible_cards.ordered
    scope = scope.where(after_anchor_condition(anchor)) if anchor.present?

    scope.limit(clamped_limit + 1).ids
  end

  def payload_cards(ids)
    return [] if ids.blank?

    cards_by_id = KanbanCard
                  .where(id: ids)
                  .includes(
                    conversation: { assignee: { avatar_attachment: :blob } },
                    contact: { avatar_attachment: :blob },
                    inbox: [:channel, { avatar_attachment: :blob }]
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
    return if ids.length <= clamped_limit || page_ids.blank?

    { after_id: page_ids.last }
  end

  def clamped_limit
    @clamped_limit ||= (limit || DEFAULT_LIMIT).to_i.clamp(1, MAX_LIMIT)
  end

  def cursor_after_id
    return if cursor.blank?

    cursor[:after_id] || cursor['after_id']
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
end
