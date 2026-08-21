class KanbanAutomations::RunRulesJob < ApplicationJob
  queue_as :low

  def perform(card_id, rule_ids, event_name, context = {})
    card = KanbanCard.active.find_by(id: card_id)
    return if card.blank?
    return unless KanbanAutomations::GuardrailService.automations_enabled?(card)

    rules_for(card, rule_ids, event_name).each do |rule|
      begin
        card.reload
      rescue ActiveRecord::RecordNotFound
        break
      end

      next unless matches?(card, rule)

      KanbanAutomations::ActionExecutor.new(card: card, rule: rule, context: context).perform
      break if rule.stop_after_match?
    end
  end

  private

  # A rule that blows up while being matched must not take the rest of the queue with it,
  # and must not disappear either: the log row is where an admin sees that it never ran.
  def matches?(card, rule)
    KanbanAutomations::RuleMatcher.match?(card, rule)
  rescue StandardError => e
    KanbanAutomationLog.create!(
      account_id: card.account_id,
      kanban_automation_rule: rule,
      kanban_card: card,
      event_name: rule.event_name,
      status: 'failed',
      details: { error_class: e.class.name, error: e.message }
    )
    ChatwootExceptionTracker.new(e, account: card.account).capture_exception
    false
  end

  def rules_for(card, rule_ids, event_name)
    KanbanAutomationRule.active
                        .where(id: Array(rule_ids), kanban_board_id: card.kanban_board_id, event_name: event_name)
                        .ordered
  end
end
