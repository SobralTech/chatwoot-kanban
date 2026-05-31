# rubocop:disable Metrics/ClassLength
class Api::V1::Accounts::KanbanBoards::CardsController < Api::V1::Accounts::BaseController
  before_action :fetch_kanban_board
  before_action :authorize_kanban_board_show
  before_action :fetch_conversation, only: [:create]
  before_action :authorize_conversation, only: [:create]
  before_action :fetch_mutation_target, only: [:update, :destroy, :reorder]
  before_action :authorize_mutation_target, only: [:update, :destroy, :reorder]
  before_action :fetch_kanban_stage, only: [:create, :update]

  def create
    ConversationKanbanState.transaction do
      @conversation_kanban_state = @kanban_board.conversation_kanban_states.find_or_initialize_by(conversation: @conversation)
      @conversation_kanban_state.assign_attributes(conversation_kanban_state_attributes)
      @conversation_kanban_state.save!

      @conversation_kanban_state.reload
      sync_service_for(@conversation_kanban_state).sync!
    end
  end

  def update
    return update_kanban_card if stable_card_route?

    previous_stage = @conversation_kanban_state.kanban_stage

    ConversationKanbanState.transaction do
      normalize_cards_for_stage(previous_stage)
      normalize_cards_for_stage(@kanban_stage) if previous_stage != @kanban_stage

      @conversation_kanban_state.reload
      @conversation_kanban_state.update!(conversation_kanban_state_attributes)

      normalize_cards_for_stage(previous_stage)
      normalize_cards_for_stage(@kanban_stage) if previous_stage != @kanban_stage
      @conversation_kanban_state.reload
      sync_states_for_stages(previous_stage, @kanban_stage)
    end
  end

  def reorder
    return reorder_kanban_card if stable_card_route?

    ConversationKanbanState.transaction do
      previous_stage = @conversation_kanban_state.kanban_stage

      if reorder_with_position?
        reorder_to_position!
      elsif %w[up down].include?(params[:direction])
        normalize_cards_for_stage(@conversation_kanban_state.kanban_stage)
        @conversation_kanban_state.reload

        sibling_state = sibling_state_for_reorder
        swap_positions(@conversation_kanban_state, sibling_state) if sibling_state

        normalize_cards_for_stage(@conversation_kanban_state.kanban_stage)
        @conversation_kanban_state.reload
      end

      sync_states_for_stages(previous_stage, @conversation_kanban_state.kanban_stage)
    end

    render :update
  end

  def destroy
    return destroy_kanban_card if stable_card_route?

    source_stage = @conversation_kanban_state.kanban_stage

    ConversationKanbanState.transaction do
      sync_service_for(@conversation_kanban_state).deactivate!
      @conversation_kanban_state.destroy!

      normalize_cards_for_stage(source_stage)
      sync_states_for_stage(source_stage)
    end

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

  def fetch_mutation_target
    return fetch_kanban_card || fetch_legacy_mutation_target if params[:id].present?

    fetch_legacy_mutation_target
  rescue ActiveRecord::RecordNotFound
    fetch_kanban_card || raise
  end

  def fetch_kanban_card
    @kanban_card = @kanban_board.kanban_cards.active.find_by(id: card_identifier)
    return true if @kanban_card
    raise ActiveRecord::RecordNotFound if KanbanCard.exists?(id: card_identifier)

    false
  end

  def fetch_legacy_mutation_target
    fetch_conversation
    fetch_conversation_kanban_state
  end

  def fetch_conversation_kanban_state
    @conversation_kanban_state = @kanban_board.conversation_kanban_states.find_by!(conversation: @conversation)
  end

  def authorize_mutation_target
    return authorize @kanban_card, action_name_policy if stable_card_route?

    authorize_conversation
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

  def card_identifier
    params[:id] || params[:conversation_id]
  end

  def stable_card_route?
    @kanban_card.present?
  end

  def action_name_policy
    "#{action_name}?".to_sym
  end

  def sibling_state_for_reorder
    ordered_states = @kanban_board
                     .conversation_kanban_states
                     .where(kanban_stage_id: @conversation_kanban_state.kanban_stage_id)
                     .ordered
                     .to_a
    state_index = ordered_states.index(@conversation_kanban_state)
    offset = params[:direction] == 'up' ? -1 : 1

    ordered_states[state_index + offset] if state_index && (state_index + offset).between?(0, ordered_states.length - 1)
  end

  def swap_positions(state, sibling_state)
    ConversationKanbanState.transaction do
      state_position = state.position
      state.update!(position: sibling_state.position)
      sibling_state.update!(position: state_position)
    end
  end

  def normalize_cards_for_stage(kanban_stage)
    ConversationKanbanState.normalize_positions_for_stage!(kanban_board: @kanban_board, kanban_stage: kanban_stage)
  end

  def sync_states_for_stages(*kanban_stages)
    kanban_stages.uniq.each { |kanban_stage| sync_states_for_stage(kanban_stage) }
  end

  def sync_states_for_stage(kanban_stage)
    @kanban_board.conversation_kanban_states.where(kanban_stage: kanban_stage).ordered.each do |state|
      sync_service_for(state).sync!
    end
  end

  def sync_service_for(conversation_kanban_state)
    KanbanCards::SyncConversationStateService.new(conversation_kanban_state)
  end

  def update_kanban_card
    source_stage = @kanban_card.kanban_stage

    KanbanCard.transaction do
      @kanban_card.reorder_to_position!(
        kanban_stage: @kanban_stage,
        position: card_params[:position] || next_card_position(@kanban_stage)
      )
      sync_legacy_states_for_card_stages(source_stage, @kanban_card.reload.kanban_stage)
    end

    render_card
  end

  def reorder_kanban_card
    source_stage = @kanban_card.kanban_stage

    KanbanCard.transaction do
      @kanban_card.reorder_to_position!(
        kanban_stage: target_card_stage_for_reorder,
        position: params.dig(:card, :position) || @kanban_card.position
      )
      sync_legacy_states_for_card_stages(source_stage, @kanban_card.reload.kanban_stage)
    end

    render_card
  end

  def destroy_kanban_card
    source_stage = @kanban_card.kanban_stage

    KanbanCard.transaction do
      @kanban_card.update!(active: false)
      legacy_state_for(@kanban_card)&.destroy! if @kanban_card.conversation?
      sync_legacy_states_for_card_stages(source_stage)
    end

    head :no_content
  end

  def next_card_position(kanban_stage)
    @kanban_board.kanban_cards.active.where(kanban_stage: kanban_stage).maximum(:position).to_i + 1
  end

  def target_card_stage_for_reorder
    stage_id = params.dig(:card, :kanban_stage_id)
    return @kanban_card.kanban_stage if stage_id.blank?

    @kanban_board.kanban_stages.active.find(stage_id)
  end

  def sync_legacy_states_for_card_stages(*kanban_stages)
    kanban_stages.uniq.each do |kanban_stage|
      @kanban_board.kanban_cards.conversation.active.where(kanban_stage: kanban_stage).ordered.each do |card|
        sync_legacy_state_for_card(card)
      end
    end
  end

  def sync_legacy_state_for_card(card)
    state = @kanban_board.conversation_kanban_states.find_or_initialize_by(conversation: card.conversation)
    state.assign_attributes(
      account: Current.account,
      kanban_board: @kanban_board,
      kanban_stage: card.kanban_stage,
      position: card.position,
      moved_by: Current.user.is_a?(User) ? Current.user : nil,
      moved_at: Time.current
    )
    state.save!
  end

  def legacy_state_for(card)
    @kanban_board.conversation_kanban_states.find_by(conversation: card.conversation)
  end

  def render_card
    render json: {
      id: @kanban_card.id,
      account_id: @kanban_card.account_id,
      kanban_board_id: @kanban_card.kanban_board_id,
      kanban_stage_id: @kanban_card.kanban_stage_id,
      conversation_id: @kanban_card.conversation&.display_id,
      position: @kanban_card.position,
      origin: @kanban_card.origin,
      subject: @kanban_card.subject,
      active: @kanban_card.active
    }
  end

  def reorder_with_position?
    params[:card].present? && (params.dig(:card, :position).present? || params.dig(:card, :kanban_stage_id).present?)
  end

  def reorder_to_position!
    @conversation_kanban_state.reorder_to_position!(
      target_stage: target_stage_for_reorder,
      target_position: params.dig(:card, :position),
      moved_by: Current.user.is_a?(User) ? Current.user : nil,
      moved_at: Time.current
    )
  end

  def target_stage_for_reorder
    stage_id = params.dig(:card, :kanban_stage_id)
    return @conversation_kanban_state.kanban_stage if stage_id.blank?

    @kanban_board.kanban_stages.active.find(stage_id)
  end
end
# rubocop:enable Metrics/ClassLength
