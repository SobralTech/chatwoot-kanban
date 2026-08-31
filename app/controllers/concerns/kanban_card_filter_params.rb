module KanbanCardFilterParams
  CARD_STATUSES = %w[open won lost].freeze
  DUE_DATES = %w[none overdue day week month].freeze
  CREATED_DATES = %w[day week month].freeze

  private

  def sanitized_inbox_filter_ids
    return @sanitized_inbox_filter_ids if defined?(@sanitized_inbox_filter_ids)

    inbox_ids = normalized_integer_filter_ids(:inbox_ids)
    @sanitized_inbox_filter_ids =
      if inbox_ids.blank?
        nil
      else
        validate_account_scoped_ids!(Inbox.where(account_id: Current.account.id, id: inbox_ids), inbox_ids)
        inbox_ids & board_filterable_inbox_ids(inbox_ids)
      end
  end

  def sanitized_assignee_filter_ids
    return @sanitized_assignee_filter_ids if defined?(@sanitized_assignee_filter_ids)

    assignee_ids = normalized_integer_filter_ids(:assignee_ids)
    @sanitized_assignee_filter_ids =
      if assignee_ids.blank?
        nil
      else
        validate_account_scoped_ids!(Current.account.account_users.where(user_id: assignee_ids), assignee_ids)
        assignee_ids
      end
  end

  def sanitized_card_statuses = sanitized_filter_values(:card_statuses, CARD_STATUSES)

  def sanitized_priorities = sanitized_filter_values(:priorities, KanbanCard.priorities.keys + ['none'])

  def sanitized_due_dates = sanitized_filter_values(:due_dates, DUE_DATES)

  def sanitized_created_dates = sanitized_filter_values(:created_dates, CREATED_DATES)

  def sanitized_labels
    return @sanitized_labels if defined?(@sanitized_labels)

    label_names = normalized_filter_values(:labels)
    selected_label_names = label_names - ['none']
    valid_label_names = Current.account.labels.where(title: selected_label_names).pluck(:title)
    valid_label_names << 'none' if label_names.include?('none')
    @sanitized_labels = valid_label_names.presence
  end

  def sanitized_match_mode
    return @sanitized_match_mode if defined?(@sanitized_match_mode)

    @sanitized_match_mode =
      if params[:match_mode].in?(KanbanCards::VisibleCardsScope::MATCH_MODES)
        params[:match_mode]
      else
        KanbanCards::VisibleCardsScope::DEFAULT_MATCH_MODE
      end
  end

  def sanitized_terminal_period
    @sanitized_terminal_period ||=
      params[:terminal_period].to_s.presence_in(KanbanCards::VisibleStageCardsQuery::TERMINAL_PERIOD_VALUES) ||
      KanbanCards::VisibleStageCardsQuery::DEFAULT_TERMINAL_PERIOD
  end

  def sanitized_collapsed_stage_ids = @sanitized_collapsed_stage_ids ||= normalized_integer_filter_ids(:collapsed_stage_ids)

  def sanitized_search_query
    return @sanitized_search_query if defined?(@sanitized_search_query)

    query = params[:q].to_s.strip.gsub(/\s+/, ' ').first(100)
    @sanitized_search_query = query.length >= 2 ? query : nil
  end

  # Every card query on a board reads the same visibility rules and the same request
  # filters, so they share one relation instead of each rebuilding it from raw params.
  # The terminal period is not part of it: only the stage columns slice by it.
  def visible_cards_scope
    @visible_cards_scope ||= KanbanCards::VisibleCardsScope.new(
      account: Current.account,
      user: Current.user,
      kanban_board: @kanban_board,
      account_user: Current.account_user,
      **kanban_card_filter_params
    ).call
  end

  def kanban_card_filter_params
    {
      filtered_inbox_ids: sanitized_inbox_filter_ids,
      filtered_assignee_ids: sanitized_assignee_filter_ids,
      filtered_card_statuses: sanitized_card_statuses,
      filtered_priorities: sanitized_priorities,
      filtered_due_dates: sanitized_due_dates,
      filtered_created_dates: sanitized_created_dates,
      filtered_labels: sanitized_labels,
      match_mode: sanitized_match_mode,
      search_query: sanitized_search_query
    }
  end

  def normalized_integer_filter_ids(key)
    Array(params[key]).filter_map(&:presence).map(&:to_i).uniq
  end

  def sanitized_filter_values(key, allowed_values)
    normalized_filter_values(key).intersection(allowed_values).presence
  end

  def normalized_filter_values(key)
    Array(params[key]).filter_map(&:presence).map(&:to_s).uniq
  end

  # A filter id that does not exist in the account is a malformed request, not an
  # empty result, so both id filters reject the whole request the same way.
  def validate_account_scoped_ids!(scope, ids)
    return if scope.count == ids.length

    raise ActiveRecord::RecordInvalid, @kanban_board
  end

  def board_filterable_inbox_ids(inbox_ids)
    return inbox_ids if @kanban_board.derived_all_inboxes?

    inbox_ids & @kanban_board.derived_allowed_inbox_ids
  end
end
