class Api::V1::Accounts::Conversations::DirectUploadsController < ActiveStorage::DirectUploadsController
  include DeviseTokenAuth::Concerns::SetUserByToken
  include RequestExceptionHandler
  include AccessTokenAuthHelper
  include EnsureCurrentAccountHelper
  include Pundit::Authorization
  include MfaEnforcementGuard

  rescue_from Pundit::NotAuthorizedError, with: :render_pundit_unauthorized

  skip_before_action :verify_authenticity_token, if: :authenticate_by_access_token?

  around_action :handle_with_exception
  before_action :authenticate_access_token!, if: :authenticate_by_access_token?
  before_action :validate_bot_access_token!, if: :authenticate_by_access_token?
  before_action :authenticate_user!, unless: :authenticate_by_access_token?
  before_action :set_current_user, unless: :authenticate_by_access_token?
  before_action :current_account
  before_action :validate_token_api_access, if: :authenticate_by_access_token?
  before_action :check_account_mfa_enforcement, if: :authenticate_by_access_token?
  before_action :conversation

  def create
    return if @conversation.nil? || @current_account.nil?

    super
  end

  private

  def validate_token_api_access
    return if Current.account.api_and_webhooks_enabled?

    render json: { error: 'API access is not enabled for this account' }, status: :forbidden
  end

  def render_pundit_unauthorized(exception)
    log_handled_error(exception)
    render_unauthorized('You are not authorized to do this action')
  end

  def set_current_user
    @user ||= Current.user || current_user
    Current.user = @user
  end

  def pundit_user
    {
      user: Current.user,
      account: Current.account,
      account_user: Current.account_user
    }
  end

  def conversation
    @conversation ||= Current.account.conversations.find_by(display_id: params[:conversation_id])
    authorize @conversation, :show? if @conversation.present?
  end
end
