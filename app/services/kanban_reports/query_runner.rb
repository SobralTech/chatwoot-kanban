class KanbanReports::QueryRunner
  QUERY_CLASSES = {
    conversion: KanbanReports::ConversionQuery,
    stage_times: KanbanReports::StageTimeQuery,
    won_lost: KanbanReports::WonLostQuery,
    loss_reasons: KanbanReports::LossReasonsQuery,
    agents: KanbanReports::AgentsQuery,
    products: KanbanReports::ProductsQuery
  }.freeze

  def self.call(report:, **)
    query_class = QUERY_CLASSES.fetch(report.to_sym)
    query_class.new(**).call
  end
end
