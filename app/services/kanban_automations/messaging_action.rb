class KanbanAutomations::MessagingAction
  def self.render_content(card:, content:)
    new(card: card, rule: nil, content: content, private_note: false, persist: false).send(:render_content)
  end

  def self.perform(card:, rule:, rendered_content:, private_note:, persist:)
    new(
      card: card,
      rule: rule,
      content: rendered_content,
      private_note: private_note,
      persist: persist
    ).perform
  end

  def initialize(card:, rule:, content:, private_note:, persist:)
    @card = card
    @rule = rule
    @content = content
    @private_note = private_note
    @persist = persist
  end

  def perform
    rendered_content = content.to_s
    raise ArgumentError, 'message content cannot be blank' if rendered_content.blank?
    return { content: rendered_content } unless persist

    message = Messages::MessageBuilder.new(nil, card.conversation, message_params(rendered_content)).perform
    { content: rendered_content, message_id: message.id }
  end

  private

  attr_reader :card, :rule, :content, :private_note, :persist

  def render_content
    Liquid::Template.parse(content.to_s).render(template_variables)
  end

  def template_variables
    {
      'card' => card_variables,
      'contact' => contact_variables,
      'subject' => card.subject,
      'total_value' => card.total_value.to_s,
      'card_subject' => card.subject.to_s,
      'contact_name' => card.contact.name.to_s,
      'agent_name' => card.assignees.order(:id).first&.name.to_s,
      'total' => card.total_value.to_s
    }
  end

  def card_variables
    {
      'id' => card.id,
      'subject' => card.subject,
      'total_value' => card.total_value.to_s,
      'stage' => { 'id' => card.kanban_stage_id, 'name' => card.kanban_stage.name }
    }
  end

  def contact_variables
    { 'id' => card.contact_id, 'name' => card.contact.name }
  end

  def message_params(rendered_content)
    {
      content: rendered_content,
      private: private_note,
      content_attributes: { automation_rule_id: rule.id }
    }
  end
end
