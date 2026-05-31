class Api::V1::Accounts::KanbanBoardsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_kanban_board, only: [:show, :update, :destroy]

  def index
    @kanban_boards = KanbanBoard.where(account_id: Current.account.id).active.ordered
  end

  def show
    @kanban_stages = @kanban_board.kanban_stages.active.ordered
    if kanban_card_board_reads_enabled?
      fetch_kanban_cards
      return
    end

    @conversation_kanban_states = @kanban_board
                                  .conversation_kanban_states
                                  .includes(conversation: [:contact, :inbox, :assignee, :team])
                                  .ordered
                                  .select { |state| policy(state.conversation).show? }
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
    params.require(:kanban_board).permit(:name, :description, :position, :active, :auto_create_cards_from_conversations, :default_stage_id)
  end

  def kanban_card_board_reads_enabled?
    Current.account.feature_enabled?('kanban_card_board_reads')
  end

  def fetch_kanban_cards
    @kanban_cards = @kanban_board
                    .kanban_cards
                    .active
                    .conversation
                    .where.not(conversation_id: nil)
                    .includes(conversation: [:contact, :contact_inbox, :inbox, :assignee, :team])
                    .ordered
                    .select { |card| policy(card.conversation).show? }
    @conversation_kanban_states_by_conversation_id = @kanban_board
                                                     .conversation_kanban_states
                                                     .where(conversation_id: @kanban_cards.map(&:conversation_id))
                                                     .index_by(&:conversation_id)
  end
end
