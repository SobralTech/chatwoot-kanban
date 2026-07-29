class Api::V1::Accounts::KanbanBoards::CustomFieldsController < Api::V1::Accounts::BaseController
  before_action :fetch_kanban_board
  before_action :authorize_kanban_board_update
  before_action :fetch_kanban_custom_field, only: [:update, :destroy]

  def index
    @kanban_custom_fields = @kanban_board.kanban_custom_fields.active.ordered
  end

  def create
    @kanban_custom_field = @kanban_board.kanban_custom_fields.create!(
      custom_field_params.merge(account: Current.account, position: next_position)
    )
    dispatch_kanban_board_event
  end

  def update
    @kanban_custom_field.update!(custom_field_params)
    dispatch_kanban_board_event
  end

  def destroy
    @kanban_custom_field.update!(active: false)
    dispatch_kanban_board_event
    head :no_content
  end

  private

  def fetch_kanban_board
    @kanban_board = policy_scope(KanbanBoard).find(params[:kanban_board_id])
  end

  def authorize_kanban_board_update
    authorize @kanban_board, :update?
  end

  def fetch_kanban_custom_field
    @kanban_custom_field = @kanban_board.kanban_custom_fields.active.find(params[:id])
  end

  def custom_field_params
    params.require(:custom_field).permit(:key, :field_type, :multiple)
  end

  def next_position
    @kanban_board.kanban_custom_fields.active.maximum(:position).to_i + 1
  end

  def dispatch_kanban_board_event
    Rails.configuration.dispatcher.dispatch(
      Events::Types::KANBAN_BOARD_UPDATED,
      Time.zone.now,
      account_id: @kanban_board.account_id,
      board_id: @kanban_board.id
    )
  end
end
