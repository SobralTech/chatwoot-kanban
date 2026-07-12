# == Schema Information
#
# Table name: channel_waha
#
#  id                 :bigint           not null, primary key
#  api_key            :string           not null
#  auto_read_receipts :boolean          default(TRUE), not null
#  auto_reconnect     :boolean          default(TRUE), not null
#  groups_enabled     :boolean          default(FALSE), not null
#  phone_number       :string
#  session_name       :string           not null
#  session_status     :string
#  status_history     :jsonb
#  waha_url           :string           not null
#  webhook_token      :string           not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :integer          not null
#
# Indexes
#
#  index_channel_waha_on_account_id     (account_id)
#  index_channel_waha_on_webhook_token  (webhook_token) UNIQUE
#
class Channel::Waha < ApplicationRecord
  include Channelable

  self.table_name = 'channel_waha'
  EDITABLE_ATTRS = [:phone_number, :waha_url, :api_key, :session_name,
                    :groups_enabled, :auto_reconnect, :auto_read_receipts].freeze

  before_validation :sanitize_session_name
  before_create :generate_webhook_token
  after_create :start_waha_session
  before_destroy :cleanup_waha_session
  validates :waha_url, :api_key, :session_name, presence: true

  def name
    'Waha'
  end

  def webhook_url
    "#{ENV.fetch('FRONTEND_URL', nil)}/webhooks/waha/#{webhook_token}"
  end

  def update_session_status(status)
    history_entry = { status: status, timestamp: Time.current.iso8601 }
    new_history = (status_history + [history_entry]).last(20)
    # rubocop:disable Rails/SkipsModelValidations
    update_columns(session_status: status, status_history: new_history)
    # rubocop:enable Rails/SkipsModelValidations
  end

  private

  def sanitize_session_name
    return if session_name.blank?

    self.session_name = session_name.strip.gsub(/[^a-zA-Z0-9._-]+/, '_')
  end

  def generate_webhook_token
    self.webhook_token = SecureRandom.uuid
  end

  def start_waha_session
    Waha::SessionService.new(channel: self).start
  end

  def cleanup_waha_session
    Waha::SessionService.new(channel: self).delete_session
  end
end
