# Works out which board, stage and card a conversation-level Kanban action should act
# on, and records why when it cannot. Every miss is a logged skip and never an
# exception: one stale board id must not stop the rest of the rule.
class KanbanCards::ActionTarget
  attr_reader :board, :stage

  def initialize(conversation:, action_name:, params:)
    @conversation = conversation
    @action_name = action_name
    @params = normalize(params)
  end

  def resolve(stage_required: true)
    @board = KanbanBoard.active.find_by(account_id: conversation.account_id, id: params[:kanban_board_id])
    return skip('board is missing or inactive') if board.blank?
    return true unless stage_required

    @stage = board.kanban_stages.active.find_by(id: params[:kanban_stage_id])
    return skip('stage is missing or inactive') if stage.blank?

    true
  end

  def agent_ids
    Array(params[:agent_ids]).filter_map(&:presence).map(&:to_i).uniq
  end

  # The card this conversation put on the board, or failing that any active
  # non-terminal card the contact already has there.
  def active_card
    @active_card ||= KanbanCard.active.find_by(kanban_board: board, conversation_id: conversation.id) ||
                     KanbanCard.active_non_terminal_for(board, conversation.contact_id).ordered.first
  end

  # Deliberately narrower than active_card: a second card for the same conversation is
  # what the unique index rejects, regardless of which contact card exists.
  def conversation_card_exists?
    KanbanCard.where(origin: :conversation).exists?(kanban_board: board, conversation_id: conversation.id)
  end

  def terminal_stage?
    KanbanStage.special_stage_ids(board).include?(stage.id)
  end

  # Won by automation is a business decision and stays manual. Lost is allowed unless
  # the board insists on a reason, which a conversation rule has no way to supply.
  def move_blocked_reason
    return 'won stage transitions are not automated' if stage.id == board.won_stage_id
    return 'lost stage requires a reason' if stage.id == board.lost_stage_id && board.lost_reason_required?

    nil
  end

  def unassignable_agents(ids)
    ids - board.assignable_users.where(id: ids).pluck(:id)
  end

  def skip(reason)
    Rails.logger.info(
      "Kanban action #{action_name} skipped: #{reason} " \
      "(account=#{conversation.account_id}, board=#{board&.id || params[:kanban_board_id]}, stage=#{stage&.id})"
    )
    false
  end

  private

  attr_reader :conversation, :action_name, :params

  # Automation and macro action_params arrive as a one-element array around the hash.
  def normalize(value)
    value = value.first if value.is_a?(Array)
    return {}.with_indifferent_access unless value.is_a?(Hash) || value.respond_to?(:to_h)

    value.to_h.with_indifferent_access
  end
end
