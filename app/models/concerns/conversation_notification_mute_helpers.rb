module ConversationNotificationMuteHelpers
  extend ActiveSupport::Concern

  def mute_notifications!
    update!(additional_attributes: additional_attributes.merge('notifications_muted' => true))
  end

  def unmute_notifications!
    update!(additional_attributes: additional_attributes.except('notifications_muted'))
  end

  def notifications_muted?
    ActiveModel::Type::Boolean.new.cast(additional_attributes['notifications_muted'])
  end
end
