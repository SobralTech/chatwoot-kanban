class KanbanReports::AgentsQuery < KanbanReports::BaseQuery
  def call
    terminal_events = unique_terminal_events
    assignees = assignees_by_card(card_ids_for_events(terminal_events))
    users = users_by_id(assignees)
    rows = rows_by_user(terminal_events, assignees)
    won_metrics = won_metrics_by_user(rows)
    rows = rows.filter_map { |user_id, counts| agent_row(users[user_id], counts, won_metrics[user_id]) }

    rows.sort_by { |row| [-row[:won], -row[:lost], row[:agent_name].to_s] }
  end

  private

  def assignees_by_card(card_ids)
    KanbanCardAssignee
      .where(account_id: account.id, kanban_card_id: card_ids)
      .pluck(:kanban_card_id, :user_id)
      .group_by(&:first)
  end

  def users_by_id(assignees)
    user_ids = assignees.values.flatten(1).map(&:last).uniq
    account.users.where(id: user_ids).index_by(&:id)
  end

  def rows_by_user(events, assignees)
    events.each_with_object(Hash.new { |hash, user_id| hash[user_id] = { won: [], lost: [] } }) do |event, rows|
      assignees.fetch(event.kanban_card_id, []).each do |(_, user_id)|
        rows[user_id][event.event_type.to_sym] << event.kanban_card_id
      end
    end
  end

  def won_metrics_by_user(rows)
    won_card_ids = rows.values.flat_map { |counts| counts[:won] }.uniq
    scope = filtered_cards.where(id: won_card_ids).joins(:kanban_card_assignees)

    KanbanCards::Totals.grouped_metrics(scope, 'kanban_card_assignees.user_id')
  end

  def agent_row(user, counts, won_metric)
    return if user.blank?

    won_ids = counts[:won].uniq
    lost_ids = counts[:lost].uniq
    won_metric ||= KanbanCards::Totals::Metric.new(0, BigDecimal(0))
    total_terminal_count = won_ids.length + lost_ids.length

    {
      agent_id: user.id,
      agent_name: user.available_name,
      won: won_ids.length,
      lost: lost_ids.length,
      conversion_rate: percentage(won_ids.length, total_terminal_count),
      revenue: KanbanCards::Totals.decimal_string(won_metric.value),
      average_ticket: average_ticket(won_metric)
    }
  end

  def average_ticket(metric)
    return '0.00' if metric.count.zero?

    format('%.2f', metric.value / metric.count)
  end
end
