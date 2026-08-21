# Puts an automation's message on the card's conversation. The content arrives already
# rendered; `persist` is what separates a real send from a simulated one, and it is
# decided by the executor, not here.
module KanbanAutomations::MessagingAction
  module_function

  def perform(card:, rule:, rendered_content:, private_note:, persist:)
    content = rendered_content.to_s
    raise ArgumentError, 'message content cannot be blank' if content.blank?
    return { content: content } unless persist

    message = Messages::MessageBuilder.new(nil, card.conversation, message_params(rule, content, private_note)).perform
    { content: content, message_id: message.id }
  end

  def message_params(rule, content, private_note)
    {
      content: content,
      private: private_note,
      content_attributes: { automation_rule_id: rule.id }
    }
  end
end
