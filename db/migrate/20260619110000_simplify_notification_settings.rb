class SimplifyNotificationSettings < ActiveRecord::Migration[7.0]
  NOTIFICATION_TYPES = {
    conversation_creation: 1,
    conversation_assignment: 2,
    assigned_conversation_new_message: 3,
    conversation_mention: 4,
    participating_conversation_new_message: 5,
    sla_missed_first_response: 6,
    sla_missed_next_response: 7,
    sla_missed_resolution: 8,
    contact_message: 9
  }.freeze

  DEFAULT_QUERY_SETTING = {
    flag_query_mode: :bit_operator,
    check_for_column: false
  }.freeze

  EMAIL_NOTIFICATION_FLAGS = NOTIFICATION_TYPES.transform_keys { |key| "email_#{key}".to_sym }.invert.freeze
  PUSH_NOTIFICATION_FLAGS = NOTIFICATION_TYPES.transform_keys { |key| "push_#{key}".to_sym }.invert.freeze

  MigrationNotificationSetting = Class.new(ApplicationRecord) do
    self.table_name = 'notification_settings'

    include FlagShihTzu

    has_flags EMAIL_NOTIFICATION_FLAGS.merge(column: 'email_flags').merge(DEFAULT_QUERY_SETTING)
    has_flags PUSH_NOTIFICATION_FLAGS.merge(column: 'push_flags').merge(DEFAULT_QUERY_SETTING)
  end

  def up
    MigrationNotificationSetting.find_each do |notification_setting|
      notification_setting.selected_email_flags = [:email_conversation_mention]
      notification_setting.selected_push_flags = [:push_conversation_mention]
      notification_setting.save!
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
