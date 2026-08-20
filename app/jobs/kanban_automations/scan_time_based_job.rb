class KanbanAutomations::ScanTimeBasedJob < ApplicationJob
  queue_as :scheduled_jobs

  TIME_BASED_EVENTS = %w[card_stalled due_soon overdue no_reply].freeze
  IDEMPOTENCY_TTL = 24.hours

  def perform
    KanbanAutomationRule.active.where(event_name: TIME_BASED_EVENTS).find_each do |rule|
      candidate_cards_for(rule).find_each do |card|
        enqueue_once(rule, card)
      end
    end
  end

  private

  def candidate_cards_for(rule)
    cards = KanbanCard.active.where(kanban_board_id: rule.kanban_board_id)
    threshold_hours = hours(rule)
    return cards.none if %w[card_stalled due_soon no_reply].include?(rule.event_name) && threshold_hours.blank?

    case rule.event_name
    when 'card_stalled'
      cards.where.not(kanban_stage_id: terminal_stage_ids(rule)).where('stage_entered_at <= ?', threshold_hours.hours.ago)
    when 'due_soon'
      now = Time.current
      cards.where(due_at: now..(now + threshold_hours.hours))
    when 'overdue'
      cards.where('due_at < ?', Time.current)
    when 'no_reply'
      no_reply_cards(cards, threshold_hours)
    else
      cards.none
    end
  end

  def no_reply_cards(cards, threshold_hours)
    cutoff = threshold_hours.hours.ago
    incoming = Message.incoming.where(private: false)
    old_messages = incoming.where('created_at < ?', cutoff).select(:conversation_id)
    recent_messages = incoming.where('created_at >= ?', cutoff).select(:conversation_id)

    cards.where(conversation_id: old_messages).where.not(conversation_id: recent_messages)
  end

  def hours(rule)
    condition = Array(rule.conditions).find { |item| item.with_indifferent_access[:attribute_key].to_s == 'hours_in_stage' }
    value = condition && Array(condition.with_indifferent_access[:values]).first
    hours = Float(value)
    raise ArgumentError unless hours.positive?

    hours
  rescue ArgumentError, TypeError
    0
  end

  def terminal_stage_ids(rule)
    KanbanStage.special_stage_ids(rule.kanban_board)
  end

  def enqueue_once(rule, card)
    key = "#{rule.id}:#{card.id}:#{rule.event_name}:#{Time.zone.today}"
    return unless Redis::Alfred.set(key, '1', nx: true, ex: IDEMPOTENCY_TTL.to_i)

    KanbanAutomations::RunRulesJob.perform_later(card.id, [rule.id], rule.event_name, {})
  end
end
