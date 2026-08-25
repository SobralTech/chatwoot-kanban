class KanbanReports::AgentsQuery < KanbanReports::BaseQuery
  def call
    terminal_events = unique_terminal_events
    assignees = assignees_by_card(card_ids_for_events(terminal_events))
    users = users_by_id(assignees)
    rows = rows_by_user(terminal_events, assignees)
    rows = rows.filter_map { |user_id, counts| agent_row(users[user_id], counts) }

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

  def agent_row(user, counts)
    return if user.blank?

    won_ids = counts[:won].uniq
    lost_ids = counts[:lost].uniq
    won_metric = metric_for(won_ids)
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
