class Api::V1::Accounts::KanbanBoards::Cards::FieldValuesController < Api::V1::Accounts::BaseController
  before_action :fetch_kanban_board
  before_action :fetch_kanban_card

  def index
    authorize @kanban_card, :show?
    fetch_field_values
  end

  def update
    authorize @kanban_card, :update?
    replace_field_values!
    fetch_field_values
    render :index
  end

  private

  def fetch_kanban_board
    @kanban_board = policy_scope(KanbanBoard).find(params[:kanban_board_id])
  end

  def fetch_kanban_card
    @kanban_card = @kanban_board.kanban_cards.active.joins(:kanban_stage).merge(KanbanStage.active).find(params[:id])
  end

  def fetch_field_values
    @kanban_card_field_values = @kanban_card.kanban_card_field_values.includes(:kanban_custom_field)
  end

  def field_values_params
    params.require(:field_values).permit!.to_h
  end

  def valid_custom_field_ids
    @valid_custom_field_ids ||= @kanban_board.kanban_custom_fields.active.pluck(:id).to_set
  end

  def replace_field_values!
    KanbanCardFieldValue.transaction do
      field_values_params.each do |custom_field_id, values|
        next unless valid_custom_field_ids.include?(custom_field_id.to_i)

        upsert_field_value(custom_field_id.to_i, Array(values))
      end
    end
  end

  def upsert_field_value(custom_field_id, values)
    if values.blank?
      @kanban_card.kanban_card_field_values.where(kanban_custom_field_id: custom_field_id).destroy_all
      return
    end

    field_value = @kanban_card.kanban_card_field_values.find_or_initialize_by(kanban_custom_field_id: custom_field_id, account: Current.account)
    field_value.update!(value: values)
  end
end
