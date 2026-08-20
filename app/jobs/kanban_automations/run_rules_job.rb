class KanbanAutomations::RunRulesJob < ApplicationJob
  queue_as :low

  def perform(card_id, rule_ids, event_name, context = {})
    card = KanbanCard.active.find_by(id: card_id)
    return if card.blank?

    rules_for(card, rule_ids, event_name).each do |rule|
      begin
        card.reload
      rescue ActiveRecord::RecordNotFound
        break
      end

      next unless KanbanAutomations::RuleMatcher.match?(card, rule)

      KanbanAutomations::ActionExecutor.new(card: card, rule: rule, context: context).perform
      break if rule.stop_after_match?
    end
  end

  private

  def rules_for(card, rule_ids, event_name)
    KanbanAutomationRule.active
                        .where(id: Array(rule_ids), kanban_board_id: card.kanban_board_id, event_name: event_name)
                        .ordered
  end
end
