class KanbanReports::DashboardQuery < KanbanReports::BaseQuery
  def call
    {
      summary: query(KanbanReports::SummaryQuery),
      conversion: query(KanbanReports::ConversionQuery),
      stage_times: query(KanbanReports::StageTimeQuery),
      won_lost: query(KanbanReports::WonLostQuery),
      loss_reasons: query(KanbanReports::LossReasonsQuery),
      agents: query(KanbanReports::AgentsQuery),
      products: query(KanbanReports::ProductsQuery)
    }
  end

  private

  def query(query_class)
    query_class.new(**query_options).call
  end

  def query_options
    {
      account: account,
      kanban_board: kanban_board,
      user: user,
      since: since,
      until: self.until,
      group_by: group_by,
      timezone_offset: timezone_offset,
      business_hours: business_hours,
      agent_ids: agent_ids,
      inbox_ids: inbox_ids,
      labels: labels,
      query_cache: dashboard_query_cache
    }
  end

  def dashboard_query_cache
    @dashboard_query_cache ||= {}
  end
end
