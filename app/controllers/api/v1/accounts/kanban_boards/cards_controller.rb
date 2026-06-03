class Api::V1::Accounts::KanbanBoards::CardsController < Api::V1::Accounts::BaseController
  before_action :fetch_kanban_board
  before_action :authorize_kanban_board_show
  before_action :fetch_manual_card_records, only: [:create_manual]
  before_action :fetch_kanban_card, only: [:show, :update, :destroy, :reorder]
  before_action :authorize_mutation_target, only: [:show, :update, :destroy, :reorder]
  before_action :fetch_kanban_stage, only: [:update]

  def show
    render_card
  end

  def create_manual
    @kanban_card = KanbanCards::CreateManualCardService.new(
      account: Current.account,
      user: Current.user,
      kanban_board: @kanban_board,
      kanban_stage: @kanban_stage,
      contact: @contact,
      inbox: @inbox,
      subject: manual_card_params[:subject]
    ).perform!

    render :create_manual, status: :created
  end

  def update
    update_kanban_card
  end

  def reorder
    reorder_kanban_card
  end

  def destroy
    destroy_kanban_card
  end

  private

  def fetch_kanban_board
    @kanban_board = KanbanBoard.active.where(account_id: Current.account.id).find(params[:kanban_board_id])
  end

  def authorize_kanban_board_show
    authorize @kanban_board, :show?
  end

  def fetch_kanban_card
    @kanban_card = @kanban_board.kanban_cards.active.joins(:kanban_stage).merge(KanbanStage.active).find(params[:id])
  end

  def authorize_mutation_target
    authorize @kanban_card, action_name_policy
  end

  def fetch_kanban_stage
    stage_id = card_params[:kanban_stage_id]
    return @kanban_stage = @kanban_card.kanban_stage if stage_id.blank?

    @kanban_stage = @kanban_board.kanban_stages.active.find(stage_id)
  end

  def fetch_manual_card_records
    @kanban_stage = @kanban_board.kanban_stages.find(manual_card_params[:kanban_stage_id])
    @contact = Current.account.contacts.find(manual_card_params[:contact_id])
    @inbox = Current.account.inboxes.find(manual_card_params[:inbox_id])
  end

  def card_params
    params.require(:card).permit(:kanban_stage_id, :position, :subject, :starts_at, :due_at)
  end

  def manual_card_params
    params.require(:card).permit(:kanban_stage_id, :contact_id, :inbox_id, :subject)
  end

  def action_name_policy
    "#{action_name}?".to_sym
  end

  def update_kanban_card
    KanbanCard.transaction do
      if stable_card_move_params?
        @kanban_card.reorder_to_position!(
          kanban_stage: @kanban_stage,
          position: card_params[:position] || target_card_position(@kanban_stage)
        )
      end
      @kanban_card.update!(stable_card_update_params)
    end

    render_card
  end

  def reorder_kanban_card
    KanbanCard.transaction do
      @kanban_card.reorder_to_position!(
        kanban_stage: target_card_stage_for_reorder,
        position: params.dig(:card, :position) || @kanban_card.position
      )
    end

    render_card
  end

  def destroy_kanban_card
    @kanban_card.deactivate_and_normalize!

    head :no_content
  end

  def next_card_position(kanban_stage)
    @kanban_board.kanban_cards.active.where(kanban_stage: kanban_stage).maximum(:position).to_i + 1
  end

  def target_card_position(kanban_stage)
    return @kanban_card.position if kanban_stage == @kanban_card.kanban_stage

    next_card_position(kanban_stage)
  end

  def stable_card_update_params
    card_params.slice(:subject, :starts_at, :due_at)
  end

  def stable_card_move_params?
    card_params[:kanban_stage_id].present? || card_params[:position].present?
  end

  def target_card_stage_for_reorder
    stage_id = params.dig(:card, :kanban_stage_id)
    return @kanban_card.kanban_stage if stage_id.blank?

    @kanban_board.kanban_stages.active.find(stage_id)
  end

  def render_card
    render partial: 'api/v1/accounts/kanban_boards/card', formats: [:json], locals: {
      card: @kanban_card,
      stable_card: true
    }
  end
end
