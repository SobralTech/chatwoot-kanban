class Api::V1::Accounts::Conversations::DirectUploadsController < ActiveStorage::DirectUploadsController
  include AccessTokenAuthHelper
  include DeviseTokenAuth::Concerns::SetUserByToken
  include EnsureCurrentAccountHelper
  include Pundit::Authorization
  include RequestExceptionHandler

  rescue_from Pundit::NotAuthorizedError, with: :render_pundit_unauthorized

  skip_before_action :verify_authenticity_token
  before_action :authenticate_access_token!, if: :authenticate_by_access_token?
  before_action :validate_bot_access_token!, if: :authenticate_by_access_token?
  before_action :authenticate_user!, unless: :authenticate_by_access_token?
  before_action :set_current_user, unless: :authenticate_by_access_token?
  before_action :current_account
  before_action :conversation
  around_action :handle_with_exception

  def create
    return if @conversation.nil? || @current_account.nil?

    super
  end

  private

  def authenticate_by_access_token?
    request.headers[:api_access_token].present? || request.headers[:HTTP_API_ACCESS_TOKEN].present?
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
