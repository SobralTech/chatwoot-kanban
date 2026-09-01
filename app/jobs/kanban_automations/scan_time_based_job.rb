class KanbanAutomations::ScanTimeBasedJob < ApplicationJob
  queue_as :scheduled_jobs

  IDEMPOTENCY_TTL = 24.hours

  def perform
    KanbanAutomationRule.active.includes(:kanban_board).where(event_name: KanbanAutomationRule::TIME_BASED_EVENTS).find_each do |rule|
      candidate_cards_for(rule).in_batches do |batch|
        batch.pluck(:id).each { |card_id| enqueue_once(rule, card_id) }
      end
    end
  end

  private

  def candidate_cards_for(rule)
    cards = KanbanCard.active.where(kanban_board_id: rule.kanban_board_id)
    threshold_hours = rule.threshold_hours.to_i
    return cards.none if rule.threshold_required? && !threshold_hours.positive?

    case rule.event_name
    when 'card_stalled'
      cards.where.not(kanban_stage_id: terminal_stage_ids(rule)).where('stage_entered_at <= ?', threshold_hours.hours.ago)
    when 'due_soon'
      now = Time.current
      cards.where(due_at: now..(now + threshold_hours.hours))
    when 'overdue'
      cards.where('due_at < ?', Time.current)
    when 'no_reply'
      no_reply_cards(cards, threshold_hours, rule.account_id)
    else
      cards.none
    end
  end

  def no_reply_cards(cards, threshold_hours, account_id)
    cutoff = threshold_hours.hours.ago
    incoming = Message.incoming
                      .where(account_id: account_id, private: false)
                      .where('messages.conversation_id = kanban_cards.conversation_id')
    old_messages = incoming.where('messages.created_at < ?', cutoff).select('1')
    recent_messages = incoming.where('messages.created_at >= ?', cutoff).select('1')

    cards.where("EXISTS (#{old_messages.to_sql})").where("NOT EXISTS (#{recent_messages.to_sql})")
  end

  def terminal_stage_ids(rule)
    KanbanStage.special_stage_ids(rule.kanban_board)
  end

  def enqueue_once(rule, card_id)
    key = "#{rule.id}:#{card_id}:#{rule.event_name}:#{Time.zone.today}"
    return unless Redis::Alfred.set(key, '1', nx: true, ex: IDEMPOTENCY_TTL.to_i)

    KanbanAutomations::RunRulesJob.perform_later(
      card_id,
      [rule.id],
      rule.event_name,
      { 'triggered_at' => Time.current.iso8601 }
    )
  end
end
