class Api::V1::Accounts::KanbanBoards::SettingsController < Api::V1::Accounts::BaseController
  before_action :fetch_kanban_board
  before_action :authorize_kanban_board

  def show; end

  def update
    ActiveRecord::Base.transaction do
      @kanban_board.update!(settings_params.except(:visible_user_ids))
      replace_memberships!
    end

    dispatch_kanban_board_event
    render :show
  end

  def import_existing_conversations
    ignore_groups = ActiveModel::Type::Boolean.new.cast(params[:ignore_groups])
    service = KanbanCards::ImportExistingConversationsService.new(
      account: Current.account,
      kanban_board: @kanban_board,
      ignore_groups: ignore_groups,
      entry_rule: entry_rule
    )

    KanbanCards::ImportExistingConversationsJob.perform_later(
      Current.account.id, @kanban_board.id, ignore_groups: ignore_groups, entry_rule_id: entry_rule&.id
    )

    render json: {
      status: 'accepted',
      enqueued: true,
      estimated_count: service.estimated_count
    }, status: :accepted
  end

  private

  def fetch_kanban_board
    # See KanbanBoardsController#fetch_kanban_board: admins need to reach the settings of a
    # deactivated board to switch it back on.
    @kanban_board = if Current.account_user&.administrator?
                      KanbanBoard.where(account_id: Current.account.id).find(params[:kanban_board_id])
                    else
                      KanbanBoard.active.where(account_id: Current.account.id).find(params[:kanban_board_id])
                    end
  end

  def authorize_kanban_board
    authorize @kanban_board, :update?
  end

  def settings_params
    params.require(:kanban_board).permit(
      :name,
      :description,
      :visibility_mode,
      :won_recurrence_enabled,
      :won_recurrence_window_hours,
      :lost_recurrence_enabled,
      :lost_recurrence_window_hours,
      :won_stage_id,
      :lost_stage_id,
      :lost_reason_required,
      automation_settings: {},
      visible_user_ids: []
    )
  end

  # An import is scoped to one entry rule, so a board with several rules imports exactly
  # what that rule would have let in rather than the union of all of them.
  def entry_rule
    return if params[:entry_rule_id].blank?

    @entry_rule ||= KanbanBoardEntryRule.where(
      account_id: Current.account.id, kanban_board_id: @kanban_board.id
    ).find(params[:entry_rule_id])
  end

  def replace_memberships!
    return unless settings_params.key?(:visible_user_ids) || @kanban_board.all_agents?

    user_ids = normalized_ids(settings_params[:visible_user_ids])
    validate_account_user_ids!(user_ids)
    KanbanBoardMember.where(kanban_board_id: @kanban_board.id).delete_all
    return if @kanban_board.all_agents? || user_ids.blank?

    user_ids.each do |user_id|
      KanbanBoardMember.create!(account: Current.account, kanban_board: @kanban_board, user_id: user_id)
    end
  end

  def normalized_ids(ids)
    Array(ids).filter_map(&:presence).map(&:to_i).uniq
  end

  def validate_account_user_ids!(user_ids)
    return if user_ids.blank?

    valid_user_count = AccountUser.where(account_id: Current.account.id, user_id: user_ids).select(:user_id).distinct.count
    return if valid_user_count == user_ids.length

    raise ActiveRecord::RecordInvalid, @kanban_board
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
