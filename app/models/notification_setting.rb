# == Schema Information
#
# Table name: notification_settings
#
#  id          :bigint           not null, primary key
#  email_flags :integer          default(0), not null
#  push_flags  :integer          default(0), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :integer
#  user_id     :integer
#
# Indexes
#
#  by_account_user  (account_id,user_id) UNIQUE
#

class NotificationSetting < ApplicationRecord
  # used for single column multi flags
  include FlagShihTzu

  belongs_to :account
  belongs_to :user

  DEFAULT_QUERY_SETTING = {
    flag_query_mode: :bit_operator,
    check_for_column: false
  }.freeze

  EMAIL_NOTIFICATION_FLAGS = ::Notification::NOTIFICATION_TYPES.transform_keys { |key| "email_#{key}".to_sym }.invert.freeze
  PUSH_NOTIFICATION_FLAGS = ::Notification::NOTIFICATION_TYPES.transform_keys { |key| "push_#{key}".to_sym }.invert.freeze
  VISIBLE_NOTIFICATION_TYPES = %w[contact_message conversation_mention].freeze
  VISIBLE_EMAIL_FLAGS = VISIBLE_NOTIFICATION_TYPES.map { |key| "email_#{key}" }.freeze
  VISIBLE_PUSH_FLAGS = VISIBLE_NOTIFICATION_TYPES.map { |key| "push_#{key}" }.freeze

  has_flags EMAIL_NOTIFICATION_FLAGS.merge(column: 'email_flags').merge(DEFAULT_QUERY_SETTING)
  has_flags PUSH_NOTIFICATION_FLAGS.merge(column: 'push_flags').merge(DEFAULT_QUERY_SETTING)

  def visible_selected_email_flags
    Array(selected_email_flags).map(&:to_s) & VISIBLE_EMAIL_FLAGS
  end

  def visible_selected_push_flags
    Array(selected_push_flags).map(&:to_s) & VISIBLE_PUSH_FLAGS
  end
end
