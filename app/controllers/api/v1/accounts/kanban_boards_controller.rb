class Api::V1::Accounts::KanbanBoardsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_kanban_board, only: [:show, :update, :destroy]

  def index
    @kanban_boards = KanbanBoard.where(account_id: Current.account.id).active.ordered
  end

  def show
    @kanban_stages = @kanban_board.kanban_stages.active.ordered
    fetch_kanban_cards
  end

  def create
    @kanban_board = KanbanBoard.create!(kanban_board_params.merge(account: Current.account))
  end

  def update
    @kanban_board.update!(kanban_board_params)
  end

  def destroy
    @kanban_board.update!(active: false)
    head :no_content
  end

  private

  def fetch_kanban_board
    @kanban_board = KanbanBoard.where(account_id: Current.account.id).active.find(params[:id])
  end

  def kanban_board_params
    params.require(:kanban_board).permit(:name, :description, :position, :active, :auto_create_cards_from_conversations)
  end

  def fetch_kanban_cards
    @kanban_cards = @kanban_board
                    .kanban_cards
                    .active
                    .joins(:kanban_stage, :contact, :inbox)
                    .left_outer_joins(:conversation)
                    .where(account_id: Current.account.id)
                    .where(kanban_stages: { account_id: Current.account.id, kanban_board_id: @kanban_board.id, active: true })
                    .where(contacts: { account_id: Current.account.id })
                    .where(inboxes: { account_id: Current.account.id })
                    .where(board_list_visibility_condition)
                    .includes(:contact, :inbox, conversation: [:contact, :contact_inbox, :inbox, :assignee, :team])
                    .ordered
  end

  def board_list_visibility_condition
    return manual_card_condition.or(valid_conversation_card_condition) if Current.account_user&.administrator?
    return valid_conversation_card_condition if Current.user.is_a?(AgentBot)

    board_list_agent_visibility_condition
  end

  def board_list_agent_visibility_condition
    conditions = []
    conditions << accessible_manual_card_condition if board_list_inbox_ids.present?
    conditions << accessible_conversation_card_condition if conversation_access_condition

    or_condition(conditions) || card_table[:id].eq(nil)
  end

  def accessible_manual_card_condition
    manual_card_condition.and(card_table[:inbox_id].in(board_list_inbox_ids))
  end

  def accessible_conversation_card_condition
    valid_conversation_card_condition.and(conversation_access_condition)
  end

  def conversation_access_condition
    @conversation_access_condition ||= or_condition(conversation_access_conditions)
  end

  def conversation_access_conditions
    conditions = []
    conditions << conversation_table[:inbox_id].in(board_list_inbox_ids) if board_list_inbox_ids.present?
    conditions << conversation_table[:team_id].in(board_list_team_ids) if board_list_team_ids.present?
    conditions
  end

  def valid_conversation_card_condition
    condition = card_table[:conversation_id].not_eq(nil)
    condition = condition.and(conversation_table[:account_id].eq(Current.account.id))
    condition = condition.and(conversation_table[:contact_id].eq(card_table[:contact_id]))
    condition.and(conversation_table[:inbox_id].eq(card_table[:inbox_id]))
  end

  def manual_card_condition
    card_table[:conversation_id].eq(nil)
  end

  def or_condition(conditions)
    conditions.reduce { |condition, next_condition| condition.or(next_condition) }
  end

  def board_list_inbox_ids
    @board_list_inbox_ids ||= Current.user.inboxes.where(account_id: Current.account.id).pluck(:id)
  end

  def board_list_team_ids
    @board_list_team_ids ||= Current.user.teams.where(account_id: Current.account.id).pluck(:id)
  end

  def card_table
    KanbanCard.arel_table
  end

  def conversation_table
    Conversation.arel_table
  end
end
