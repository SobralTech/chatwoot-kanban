require 'csv'

class KanbanReports::CsvExporter
  def self.call(report:, data:)
    new(report: report, data: data).call
  end

  def initialize(report:, data:)
    @report = report.to_sym
    @data = data
  end

  def call
    CSV.generate(headers: true) do |csv|
      csv << headers
      rows.each { |row| csv << row }
    end
  end

  private

  attr_reader :report, :data

  def headers
    {
      conversion: %w[stage_id stage_name count conversion_rate],
      stage_times: %w[stage_id stage_name average_seconds median_seconds completed_count],
      won_lost: %w[period won lost],
      loss_reasons: %w[reason_id reason_title count percentage],
      agents: %w[agent_id agent_name won lost conversion_rate revenue average_ticket],
      products: %w[sku product_name quantity revenue cards_count]
    }.fetch(report)
  end

  def rows
    case report
    when :won_lost
      data.fetch(:series).map { |row| headers.map { |header| row[header.to_sym] } }
    else
      data.map { |row| headers.map { |header| row[header.to_sym] } }
    end
  end
end
