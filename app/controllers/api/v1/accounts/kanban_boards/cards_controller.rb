class Api::V1::Accounts::KanbanBoards::CardsController < Api::V1::Accounts::BaseController
  before_action :fetch_kanban_board
  before_action :authorize_kanban_board_show
  before_action :fetch_conversation
  before_action :authorize_conversation
  before_action :fetch_conversation_kanban_state, only: [:update, :destroy]
  before_action :fetch_kanban_stage, only: [:create, :update]

  def create
    @conversation_kanban_state = @kanban_board.conversation_kanban_states.find_or_initialize_by(conversation: @conversation)
    @conversation_kanban_state.assign_attributes(conversation_kanban_state_attributes)
    @conversation_kanban_state.save!
  end

  def update
    @conversation_kanban_state.update!(conversation_kanban_state_attributes)
  end

  def destroy
    @conversation_kanban_state.destroy!
    head :no_content
  end

  private

  def fetch_kanban_board
    @kanban_board = KanbanBoard.where(account_id: Current.account.id).find(params[:kanban_board_id])
  end

  def authorize_kanban_board_show
    authorize @kanban_board, :show?
  end

  def fetch_conversation
    conversation_display_id = params[:conversation_id] || card_params[:conversation_id]
    @conversation = Current.account.conversations.find_by!(display_id: conversation_display_id)
  end

  def authorize_conversation
    authorize @conversation, :show?
  end

  def fetch_conversation_kanban_state
    @conversation_kanban_state = @kanban_board.conversation_kanban_states.find_by!(conversation: @conversation)
  end

  def fetch_kanban_stage
    @kanban_stage = @kanban_board.kanban_stages.active.find(card_params[:kanban_stage_id])
  end

  def conversation_kanban_state_attributes
    {
      account: Current.account,
      kanban_board: @kanban_board,
      kanban_stage: @kanban_stage,
      position: card_params[:position] || next_position,
      moved_by: Current.user.is_a?(User) ? Current.user : nil,
      moved_at: Time.current
    }
  end

  def next_position
    @kanban_stage.conversation_kanban_states.maximum(:position).to_i + 1
  end

  def card_params
    params.require(:card).permit(:conversation_id, :kanban_stage_id, :position)
  end
end
