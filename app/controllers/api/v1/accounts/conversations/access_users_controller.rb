class Api::V1::Accounts::Conversations::AccessUsersController < Api::V1::Accounts::BaseController
  include Events::Types

  before_action :ensure_admin!
  before_action :conversation

  def show
    @conversation_access_users = @conversation.conversation_access_users.includes(:user)
  end

  def update
    users = eligible_user_ids

    revoked_user_ids = []

    @conversation.with_lock do
      before_user_ids = policy_visible_non_admin_user_ids

      @conversation.conversation_access_users.where.not(user_id: users).destroy_all
      users.each do |user_id|
        @conversation.conversation_access_users.find_or_create_by!(account: Current.account, user_id: user_id)
      end

      @conversation.conversation_access_users.reload
      revoked_user_ids = before_user_ids - policy_visible_non_admin_user_ids
    end

    dispatch_access_revoked_event(revoked_user_ids) if revoked_user_ids.present?

    @conversation_access_users = @conversation.conversation_access_users.includes(:user)
    render :show
  end

  def eligible
    @eligible_agents = Current.account.agents.select do |agent|
      ConversationPolicy.new(
        { user: agent, account: Current.account, account_user: agent.account_users.find_by(account: Current.account) }, @conversation
      ).send(:base_agent_can_view_conversation?)
    end
  end

  private

  def ensure_admin!
    render_unauthorized('You are not authorized to access this resource') unless Current.account_user&.administrator?
  end

  def conversation
    @conversation ||= Current.account.conversations.find_by!(display_id: params[:conversation_id])
  end

  def permitted_params
    params.permit(user_ids: [], access_users: { user_ids: [] })
  end

  def permitted_user_ids
    permitted_params[:user_ids] || permitted_params.dig(:access_users, :user_ids) || []
  end

  def eligible_user_ids
    Current.account.account_users.agent.where(user_id: permitted_user_ids).filter_map do |account_user|
      account_user.user_id if existing_access_user?(account_user.user_id) || base_access?(account_user)
    end
  end

  def existing_access_user?(user_id)
    @conversation.conversation_access_users.exists?(user_id: user_id)
  end

  def base_access?(account_user)
    ConversationPolicy.new(
      { user: account_user.user, account: Current.account, account_user: account_user }, @conversation
    ).send(:base_agent_can_view_conversation?)
  end

  def policy_visible_non_admin_user_ids
    Current.account.users.where.not(account_users: { role: :administrator }).select do |user|
      account_user = user.account_users.find_by(account: Current.account)
      ConversationPolicy.new(
        { user: user, account: Current.account, account_user: account_user }, @conversation
      ).show?
    end.map(&:id)
  end

  def dispatch_access_revoked_event(user_ids)
    tokens = User.where(id: user_ids).pluck(:pubsub_token)
    Rails.configuration.dispatcher.dispatch(CONVERSATION_ACCESS_REVOKED, Time.zone.now, conversation: @conversation, tokens: tokens)
  end
end
