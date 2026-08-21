# Renders the Liquid a rule author writes -- a message, a private note, the subject of a
# card an action creates. The vocabulary is exactly what the form's variable picker
# offers, plus the two objects the nested names come from; there is deliberately one
# name per value.
module KanbanAutomations::ContentRenderer
  module_function

  def render(card:, content:)
    Liquid::Template.parse(content.to_s).render(variables(card))
  end

  def variables(card)
    {
      'card' => card_variables(card),
      'contact' => { 'id' => card.contact_id, 'name' => card.contact.name },
      'card_subject' => card.subject.to_s,
      'contact_name' => card.contact.name.to_s,
      'agent_name' => card.assignees.order(:id).first&.name.to_s,
      'total' => card.total_value.to_s
    }
  end

  def card_variables(card)
    {
      'id' => card.id,
      'subject' => card.subject,
      'total_value' => card.total_value.to_s,
      'stage' => { 'id' => card.kanban_stage_id, 'name' => card.kanban_stage.name }
    }
  end
end
