class Api::V2::Accounts::KanbanReportsController < Api::V1::Accounts::BaseController
  CACHE_EXPIRATION = 5.minutes

  before_action :load_boards
  before_action :load_board

  def index
    return render json: empty_payload unless @kanban_board

    payload = cached(:dashboard) do
      KanbanReports::DashboardQuery.new(**query_options).call.merge(
        board: board_payload(@kanban_board),
        boards: boards_payload,
        selected_board_id: @kanban_board.id
      )
    end
    render json: payload
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def conversion
    render_csv(:conversion)
  end

  def stage_times
    render_csv(:stage_times)
  end

  def stage_time
    render_csv(:stage_times)
  end

  def won_lost
    render_csv(:won_lost)
  end

  def loss_reasons
    render_csv(:loss_reasons)
  end

  def reasons
    render_csv(:loss_reasons)
  end

  def agents
    render_csv(:agents)
  end

  def products
    render_csv(:products)
  end

  private

  def load_boards
    @boards = policy_scope(KanbanBoard).ordered.to_a
  end

  def load_board
    if params[:kanban_board_id].blank?
      raise ActiveRecord::RecordNotFound unless action_name == 'index'

      return
    end

    @kanban_board = @boards.find { |board| board.id == params[:kanban_board_id].to_i }
    raise ActiveRecord::RecordNotFound if @kanban_board.blank?

    authorize @kanban_board, :show?
  end

  def query_options
    {
      account: Current.account,
      kanban_board: @kanban_board,
      user: Current.user,
      since: params[:since],
      until: params[:until],
      group_by: params[:group_by].presence || 'day',
      timezone_offset: params[:timezone_offset],
      business_hours: ActiveModel::Type::Boolean.new.cast(params[:business_hours]),
      agent_ids: filter_values(:agent_ids),
      inbox_ids: filter_values(:inbox_ids),
      labels: filter_values(:labels)
    }
  end

  def filter_values(key)
    Array(params[key]).flat_map { |value| value.to_s.split(',') }.filter_map(&:presence).uniq
  end

  def cached(report, &)
    Rails.cache.fetch(cache_key(report), expires_in: CACHE_EXPIRATION, &)
  end

  def cache_key(report)
    [
      'kanban_reports',
      report,
      Current.account.id,
      @kanban_board&.id,
      Current.user&.id,
      params[:since],
      params[:until],
      params[:group_by].presence || 'day',
      params[:timezone_offset],
      params[:business_hours],
      filter_values(:agent_ids).sort,
      filter_values(:inbox_ids).sort,
      filter_values(:labels).sort
    ]
  end

  def render_csv(report)
    data = cached(report) { KanbanReports::QueryRunner.call(report: report, **query_options) }
    csv = KanbanReports::CsvExporter.call(report: report, data: data)

    send_data csv,
              filename: "kanban_#{report}_report.csv",
              type: 'text/csv; charset=utf-8',
              disposition: 'attachment'
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def empty_payload
    { boards: boards_payload, selected_board_id: nil, data: nil }
  end

  def boards_payload
    @boards.map { |board| { id: board.id, name: board.name } }
  end

  def board_payload(board)
    {
      id: board.id,
      name: board.name,
      stages: board.kanban_stages.active.ordered.map do |stage|
        {
          id: stage.id,
          name: stage.name,
          color: stage.color,
          position: stage.position,
          terminal: [board.won_stage_id, board.lost_stage_id].include?(stage.id)
        }
      end
    }
  end
end
