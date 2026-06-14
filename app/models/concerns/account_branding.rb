module AccountBranding
  extend ActiveSupport::Concern
  include Rails.application.routes.url_helpers

  BRANDING_ASSETS = {
    logo: 'logo',
    logo_dark: 'logo_dark',
    favicon: 'favicon'
  }.freeze
  ALLOWED_BRANDING_CONTENT_TYPES = %w[
    image/jpeg
    image/png
    image/gif
    image/webp
    image/svg+xml
    image/x-icon
    image/vnd.microsoft.icon
  ].freeze
  MAX_BRANDING_ASSET_SIZE = 512.kilobytes

  included do
    has_one_attached :logo
    has_one_attached :logo_dark
    has_one_attached :favicon

    validate :acceptable_branding_assets
  end

  def branding_asset_url(asset_name)
    asset = public_send(asset_name)
    return unless asset.attached?

    url_for(asset)
  end

  private

  def acceptable_branding_assets
    BRANDING_ASSETS.each_key do |asset_name|
      asset = public_send(asset_name)
      next unless asset.attached?

      errors.add(asset_name, 'is too big') if asset.byte_size > MAX_BRANDING_ASSET_SIZE
      errors.add(asset_name, 'filetype not supported') unless ALLOWED_BRANDING_CONTENT_TYPES.include?(asset.content_type)
    end
  end
end
