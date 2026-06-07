class Api::V1::Accounts::Conversations::KanbanCardsController < Api::V1::Accounts::BaseController
  before_action :fetch_conversation
  before_action :authorize_conversation_show
  before_action :fetch_kanban_board, only: [:create]
  before_action :authorize_kanban_board_show, only: [:create]
  before_action :fetch_kanban_stage, only: [:create]

  def index
    @kanban_cards = linked_kanban_cards.select { |kanban_card| KanbanCardPolicy.new(user_context, kanban_card).show? }
    @labels_by_title = Current.account.labels.where(title: linked_label_titles).index_by(&:title)
  end

  def create
    @kanban_card = KanbanCards::CreateFromConversationService.new(
      account: Current.account,
      user: Current.user,
      conversation: @conversation,
      kanban_board: @kanban_board,
      kanban_stage: @kanban_stage,
      subject: card_params[:subject],
      due_at: card_params[:due_at],
      labels: card_params[:labels]
    ).perform!

    render :create, status: :created
  end

  private

  def fetch_conversation
    @conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
  end

  def authorize_conversation_show
    authorize @conversation, :show?
  end

  def fetch_kanban_board
    @kanban_board = policy_scope(KanbanBoard).find(card_params[:kanban_board_id])
  end

  def authorize_kanban_board_show
    authorize @kanban_board, :show?
  end

  def fetch_kanban_stage
    @kanban_stage = @kanban_board.kanban_stages.find(card_params[:kanban_stage_id])
  end

  def linked_kanban_cards
    KanbanCard.where(account_id: Current.account.id)
              .active
              .where(conversation_id: @conversation.id)
              .joins(:kanban_board, :kanban_stage)
              .merge(KanbanBoard.active)
              .merge(KanbanStage.active)
              .includes(:kanban_board, :kanban_stage, :contact, :inbox, :labels)
              .order('kanban_boards.position ASC, kanban_stages.position ASC, kanban_cards.position ASC, kanban_cards.id ASC')
  end

  def card_params
    params.require(:card).permit(:kanban_board_id, :kanban_stage_id, :subject, :due_at, labels: [])
  end

  def linked_label_titles
    @kanban_cards.flat_map { |kanban_card| kanban_card.labels.map(&:name) }.uniq
  end

  def user_context
    { user: Current.user, account: Current.account, account_user: Current.account_user }
  end
end
