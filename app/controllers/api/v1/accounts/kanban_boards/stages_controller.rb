# rubocop:disable Metrics/ClassLength
class Api::V1::Accounts::KanbanBoards::StagesController < Api::V1::Accounts::BaseController
  before_action :fetch_kanban_board
  before_action :authorize_kanban_board_update
  before_action :fetch_kanban_stage, only: [:update, :destroy, :reorder, :copy, :move]

  def create
    KanbanStage.transaction do
      KanbanStage.normalize_positions_for_board!(@kanban_board)
      position = KanbanStage.next_active_position(@kanban_board)
      KanbanStage.shift_active_positions_from!(@kanban_board, position)

      @kanban_stage = @kanban_board.kanban_stages.create!(
        kanban_stage_params.except(:position).merge(account: Current.account, position: position)
      )
    end

    dispatch_kanban_stage_event(Events::Types::KANBAN_STAGE_CREATED)
  end

  def copy
    source_stage = @kanban_stage

    KanbanStage.transaction do
      KanbanStage.normalize_positions_for_board!(@kanban_board)
      source_stage.reload
      position = [source_stage.position + 1, KanbanStage.next_active_position(@kanban_board)].min
      KanbanStage.shift_active_positions_from!(@kanban_board, position)

      @kanban_stage = @kanban_board.kanban_stages.create!(
        account: Current.account,
        name: copy_stage_params[:name],
        color: source_stage.color,
        description: source_stage.description,
        position: position
      )
      KanbanStage.normalize_positions_for_board!(@kanban_board)
    end

    dispatch_kanban_stage_event(Events::Types::KANBAN_STAGE_CREATED)
    render :create
  end

  def update
    if deactivating_stage_with_active_cards?
      render_stage_not_empty_error
      return
    end

    @kanban_stage.update!(stage_update_params)
    dispatch_kanban_stage_event(Events::Types::KANBAN_STAGE_UPDATED)
  end

  def reorder
    invalid_reorder = false

    KanbanStage.transaction do
      KanbanStage.normalize_positions_for_board!(@kanban_board)
      @kanban_stage.reload
      ordered_stages = @kanban_board.kanban_stages.active.ordered.to_a
      reordered_stages = reordered_stages_for(ordered_stages)

      if reordered_stages.present? && reordered_stages != ordered_stages
        unless KanbanStage.valid_special_stage_order?(@kanban_board, reordered_stages)
          invalid_reorder = true
          raise ActiveRecord::Rollback
        end

        KanbanStage.apply_position_order!(reordered_stages)
      end

      KanbanStage.normalize_positions_for_board!(@kanban_board)
      @kanban_stage.reload
    end

    return render_invalid_stage_order if invalid_reorder

    dispatch_kanban_stage_event(Events::Types::KANBAN_STAGE_REORDERED)
    render :update
  end

  def move
    target_board = target_kanban_board
    return reorder unless target_board && target_board != @kanban_board
    return render_stage_move_error('stage_not_empty') if stage_has_active_cards?
    return render_stage_move_error('special_stage_cannot_move_board') if special_stage?

    source_board = @kanban_board
    target_position = requested_target_position(target_board)

    KanbanStage.transaction do
      KanbanStage.lock_reorder_stages_for_board!([source_board, target_board])
      KanbanStage.shift_active_positions_from!(target_board, target_position)
      @kanban_stage.update!(kanban_board: target_board, position: target_position)
      KanbanStage.normalize_positions_for_board!(source_board)
      KanbanStage.normalize_positions_for_board!(target_board)
    end

    @kanban_board = target_board
    @kanban_stage.reload
    dispatch_kanban_stage_event(Events::Types::KANBAN_STAGE_UPDATED, board_id: source_board.id)
    dispatch_kanban_stage_event(Events::Types::KANBAN_STAGE_UPDATED, board_id: target_board.id)
    render :update
  end

  def destroy
    return render_special_stage_error if special_stage?
    return render_stage_not_empty_error if stage_has_active_cards?

    KanbanStage.transaction do
      @kanban_stage.update!(active: false)
      KanbanStage.normalize_positions_for_board!(@kanban_board)
    end

    dispatch_kanban_stage_event(Events::Types::KANBAN_STAGE_DELETED)
    head :no_content
  end

  private

  def fetch_kanban_board
    @kanban_board = find_kanban_board(params[:kanban_board_id])
  end

  def find_kanban_board(board_id)
    # See KanbanBoardsController#fetch_kanban_board: admins editing a draft board (not yet
    # activated) need to manage its stages before it becomes active.
    if Current.account_user&.administrator?
      KanbanBoard.where(account_id: Current.account.id).find(board_id)
    else
      policy_scope(KanbanBoard).find(board_id)
    end
  end

  def authorize_kanban_board_update
    authorize @kanban_board, :update?
  end

  def fetch_kanban_stage
    @kanban_stage = @kanban_board.kanban_stages.active.find(params[:id])
  end

  def kanban_stage_params
    params.require(:stage).permit(:name, :position, :active, :color, :description)
  end

  def copy_stage_params
    params.require(:stage).permit(:name)
  end

  def deactivating_stage_with_active_cards?
    return false unless kanban_stage_params.key?(:active)
    return false if ActiveModel::Type::Boolean.new.cast(kanban_stage_params[:active])

    stage_has_active_cards?
  end

  def stage_has_active_cards?
    @kanban_stage.kanban_cards.active.exists?
  end

  def special_stage?
    KanbanStage.special_stage_ids(@kanban_board).include?(@kanban_stage.id)
  end

  def stage_update_params
    attributes = kanban_stage_params.except(:position)
    return attributes unless special_stage?

    attributes[:color] = if @kanban_board.won_stage_id == @kanban_stage.id
                           KanbanBoards::TemplateCatalog::WON_COLOR
                         else
                           KanbanBoards::TemplateCatalog::LOST_COLOR
                         end
    attributes
  end

  def render_special_stage_error
    render json: { error: 'special_stage_cannot_be_deleted' }, status: :unprocessable_content
  end

  # The destination board arrives as target_kanban_board_id: :kanban_board_id is the route
  # segment for the source board and would always shadow a body param of the same name.
  def target_kanban_board
    return if params[:target_kanban_board_id].blank?

    find_kanban_board(params[:target_kanban_board_id]).tap { |board| authorize board, :update? }
  end

  def requested_target_position(target_board)
    maximum_position = KanbanStage.next_active_position(target_board)
    (params[:position].presence || maximum_position).to_i.clamp(1, maximum_position)
  end

  def render_stage_not_empty_error
    render json: { error: 'Kanban stage must be empty before it can be removed. Active cards are still assigned to this stage.' },
           status: :unprocessable_content
  end

  def render_stage_move_error(error)
    render json: { error: error }, status: :unprocessable_content
  end

  def dispatch_kanban_stage_event(event_name, board_id: @kanban_stage.kanban_board_id)
    Rails.configuration.dispatcher.dispatch(
      event_name,
      Time.zone.now,
      account_id: @kanban_stage.account_id,
      board_id: board_id,
      stage_id: @kanban_stage.id
    )
  end

  def sibling_stage_for_reorder
    ordered_stages = @kanban_board.kanban_stages.active.ordered.to_a
    stage_index = ordered_stages.index(@kanban_stage)
    offset = params[:direction] == 'left' ? -1 : 1

    ordered_stages[stage_index + offset] if stage_index && (stage_index + offset).between?(0, ordered_stages.length - 1)
  end

  def reordered_stages_for(ordered_stages)
    if params[:position].present?
      move_stage_to_position(ordered_stages)
    elsif %w[left right].include?(params[:direction])
      sibling_stage = sibling_stage_for_reorder
      return ordered_stages unless sibling_stage

      swap_positions(ordered_stages, sibling_stage)
    end
  end

  def swap_positions(ordered_stages, sibling_stage)
    reordered_stages = ordered_stages.dup
    stage_index = reordered_stages.index(@kanban_stage)
    sibling_index = reordered_stages.index(sibling_stage)
    reordered_stages[stage_index], reordered_stages[sibling_index] = reordered_stages[sibling_index], reordered_stages[stage_index]
    reordered_stages
  end

  def move_stage_to_position(ordered_stages)
    current_index = ordered_stages.index(@kanban_stage)
    return unless current_index

    target_position = params[:position].to_i
    clamped_index = (target_position - 1).clamp(0, ordered_stages.length - 1)
    return if clamped_index == current_index

    reordered_stages = ordered_stages.dup
    reordered_stages.delete_at(current_index)
    reordered_stages.insert(clamped_index, @kanban_stage)
    reordered_stages
  end

  def render_invalid_stage_order
    render json: { error: KanbanStage::SPECIAL_STAGE_ORDER_ERROR }, status: :unprocessable_content
  end
end
# rubocop:enable Metrics/ClassLength
