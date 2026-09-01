class NotificationFinder
  attr_reader :current_user, :current_account, :params

  RESULTS_PER_PAGE = 15

  def initialize(current_user, current_account, params = {})
    @current_user = current_user
    @current_account = current_account
    @params = params
    set_up
  end

  def notifications
    @notifications.page(current_page).per(RESULTS_PER_PAGE).order(last_activity_at: sort_order)
  end

  def unread_count
    # If we're including read notifications, filter to unread.
    # Otherwise the scope is already unread-only and the counts are identical.
    return @unread_count ||= @notifications.where(read_at: nil).count if type_included?('read')

    count
  end

  def count
    @count ||= @notifications.count
  end

  private

  def set_up
    find_all_notifications
    filter_hidden_conversation_notifications
    filter_snoozed_notifications
    filter_read_notifications
  end

  def find_all_notifications
    @notifications = current_user.notifications.where(account_id: @current_account.id)
  end

  def filter_hidden_conversation_notifications
    permission_filter = Conversations::PermissionFilterService.new(
      @current_account.conversations,
      current_user,
      @current_account
    )
    # The subquery would span every conversation in the account without excluding anything.
    return if permission_filter.unrestricted?

    visible_conversation_ids = permission_filter.perform.select(:id)

    visible_notifications = @notifications.where(primary_actor_type: 'Conversation', primary_actor_id: visible_conversation_ids)

    @notifications = @notifications.where.not(primary_actor_type: 'Conversation').or(visible_notifications)
  end

  def filter_snoozed_notifications
    @notifications = @notifications.where(snoozed_until: nil) unless type_included?('snoozed')
  end

  def filter_read_notifications
    @notifications = @notifications.where(read_at: nil) unless type_included?('read')
  end

  def type_included?(type)
    (params[:includes] || []).include?(type)
  end

  def current_page
    params[:page] || 1
  end

  def sort_order
    params[:sort_order] || :desc
  end
end
