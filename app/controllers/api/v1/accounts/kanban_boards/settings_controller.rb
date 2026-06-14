class Api::V1::Accounts::KanbanBoards::SettingsController < Api::V1::Accounts::BaseController
  before_action :fetch_kanban_board
  before_action :authorize_kanban_board

  def show; end

  def update
    ActiveRecord::Base.transaction do
      @kanban_board.update!(settings_params.except(:visible_user_ids, :allowed_inbox_ids))
      replace_memberships!
      replace_inboxes!
    end

    dispatch_kanban_board_event
    render :show
  end

  def import_existing_conversations
    ignore_groups = ActiveModel::Type::Boolean.new.cast(params[:ignore_groups])
    service = KanbanCards::ImportExistingConversationsService.new(
      account: Current.account,
      kanban_board: @kanban_board,
      ignore_groups: ignore_groups
    )

    KanbanCards::ImportExistingConversationsJob.perform_later(Current.account.id, @kanban_board.id, ignore_groups: ignore_groups)

    render json: {
      status: 'accepted',
      enqueued: true,
      estimated_count: service.estimated_count
    }, status: :accepted
  end

  private

  def fetch_kanban_board
    @kanban_board = KanbanBoard.active.where(account_id: Current.account.id).find(params[:kanban_board_id])
  end

  def authorize_kanban_board
    authorize @kanban_board, :update?
  end

  def settings_params
    params.require(:kanban_board).permit(
      :name,
      :description,
      :visibility_mode,
      :inbox_scope_mode,
      :auto_create_cards_from_conversations,
      visible_user_ids: [],
      allowed_inbox_ids: []
    )
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

  def replace_inboxes!
    return unless settings_params.key?(:allowed_inbox_ids) || @kanban_board.all_inboxes?

    inbox_ids = normalized_ids(settings_params[:allowed_inbox_ids])
    validate_account_inbox_ids!(inbox_ids)
    KanbanBoardInbox.where(kanban_board_id: @kanban_board.id).delete_all
    return if @kanban_board.all_inboxes? || inbox_ids.blank?

    inbox_ids.each do |inbox_id|
      KanbanBoardInbox.create!(account: Current.account, kanban_board: @kanban_board, inbox_id: inbox_id)
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

  def validate_account_inbox_ids!(inbox_ids)
    return if inbox_ids.blank?

    valid_inbox_count = Inbox.where(account_id: Current.account.id, id: inbox_ids).count
    return if valid_inbox_count == inbox_ids.length

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
