class Api::V1::Accounts::KanbanBoardsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_kanban_board, only: [:show, :update, :destroy]

  def index
    @kanban_boards = KanbanBoard.where(account_id: Current.account.id).active.ordered
  end

  def show
    @kanban_stages = @kanban_board.kanban_stages.active.ordered
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
    params.require(:kanban_board).permit(:name, :description, :position, :active, :auto_create_cards_from_conversations)
  end
end
