class ConversationAssistant::SendToCustomerService
  pattr_initialize [:assistant_message!, :user!]

  class ValidationError < StandardError; end

  def perform
    validate!

    message = Messages::MessageBuilder.new(
      user,
      assistant_message.conversation,
      ActionController::Parameters.new(
        content: assistant_message.suggested_reply,
        private: false
      )
    ).perform

    assistant_message.update!(
      status: :sent_to_customer,
      sent_to_customer_at: Time.current,
      sent_message: message
    )

    message
  end

  private

  def validate!
    unless assistant_message.completed? || assistant_message.sent_to_customer?
      raise ValidationError, I18n.t('errors.conversation_assistant.not_ready')
    end
    raise ValidationError, I18n.t('errors.conversation_assistant.suggested_reply_blank') if assistant_message.suggested_reply.blank?
    raise ValidationError, I18n.t('errors.conversation_assistant.outside_messaging_window') unless assistant_message.conversation.can_reply?
  end
end
