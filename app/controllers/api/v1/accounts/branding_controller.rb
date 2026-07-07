class Api::V1::Accounts::BrandingController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  def update
    asset_name = params[:asset_name].to_s
    return head :bad_request unless branding_asset?(asset_name)

    file = params.require(:file)
    unless AccountBranding::ALLOWED_BRANDING_CONTENT_TYPES.include?(file.content_type)
      return render json: { error: 'filetype not supported' }, status: :unprocessable_entity
    end
    return render json: { error: 'is too big' }, status: :unprocessable_entity if file.size > AccountBranding::MAX_BRANDING_ASSET_SIZE

    Current.account.public_send(asset_name).attach(file)

    @account = Current.account
    render 'api/v1/accounts/show', format: :json
  end

  def destroy
    asset_name = params[:asset_name]
    return head :bad_request unless branding_asset?(asset_name)

    asset = Current.account.public_send(asset_name)
    asset.purge if asset.attached?

    @account = Current.account
    render 'api/v1/accounts/show', format: :json
  end

  private

  def branding_asset?(asset_name)
    AccountBranding::BRANDING_ASSETS.key?(asset_name&.to_sym)
  end

  def check_authorization
    authorize(Current.account, :update?)
  end
end
