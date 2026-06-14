class ConversationAssistant::SendToCustomerService
  pattr_initialize [:assistant_message!, :user!]

  def perform
    raise StandardError, 'Assistant response is not ready' unless assistant_message.completed? || assistant_message.sent_to_customer?
    raise StandardError, 'Suggested reply is blank' if assistant_message.suggested_reply.blank?

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
end
