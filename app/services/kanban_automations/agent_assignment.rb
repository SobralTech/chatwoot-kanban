# Resolves the `assign_agents` action into the list of user ids a card should end up
# with. Only ids the board actually allows survive; unknown ones are dropped rather
# than raising, so one stale agent does not sink the whole rule.
class KanbanAutomations::AgentAssignment
  MODES = %w[set add round_robin].freeze

  def self.resolve(board:, card:, params:)
    new(board: board, card: card, params: params).resolve
  end

  def initialize(board:, card:, params:)
    @board = board
    @card = card
    @params = params
  end

  def resolve
    case params[:mode].to_s
    when 'set' then assignable_ids
    when 'add' then (current_ids + assignable_ids).uniq
    when 'round_robin' then [round_robin_agent_id].compact
    else
      raise ArgumentError, "unsupported assignment mode: #{params[:mode]}"
    end
  end

  private

  attr_reader :board, :card, :params

  def current_ids
    card.kanban_card_assignees.pluck(:user_id)
  end

  def assignable_ids
    requested_ids = Array(params[:agent_ids]).filter_map { |id| Integer(id, exception: false) }
    board.assignable_users.where(id: requested_ids).pluck(:id)
  end

  # Fewest active non-terminal cards on this board wins; ties go to the lowest id so
  # the pick stays deterministic.
  def round_robin_agent_id
    agents = board.assignable_users.order(:id).to_a
    return if agents.empty?

    counts = active_card_counts(agents)
    agents.min_by { |agent| [counts.fetch(agent.id, 0), agent.id] }.id
  end

  def active_card_counts(agents)
    KanbanCard.active
              .where(kanban_board_id: board.id)
              .where.not(kanban_stage_id: KanbanStage.special_stage_ids(board))
              .joins(:kanban_card_assignees)
              .where(kanban_card_assignees: { user_id: agents.map(&:id) })
              .group(:user_id)
              .count
  end
end
