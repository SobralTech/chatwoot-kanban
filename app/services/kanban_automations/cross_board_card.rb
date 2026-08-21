# The `create_card_in_board` action: spawn a card for this card's contact on another
# board of the same account. Creating it dispatches its own realtime event, which the
# executor's rollback cannot take back, so a simulated run stops at `describe`.
class KanbanAutomations::CrossBoardCard
  def initialize(card:, rule:, context: {})
    @card = card
    @rule = rule
    @context = context
  end

  def describe(params)
    { kanban_board_id: target_board(params).id, stage_id: target_stage(params).id, subject: subject(params) }
  end

  def create!(params)
    KanbanCards::CreateManualCardService.new(
      account: card.account,
      user: nil,
      kanban_board: target_board(params),
      kanban_stage: target_stage(params),
      contact: card.contact,
      inbox: card.inbox,
      subject: subject(params),
      conversation: card.conversation,
      context: automation_context
    ).perform!
  end

  private

  attr_reader :card, :rule, :context

  def target_board(params)
    @target_board ||= KanbanBoard.where(account_id: card.account_id).find(params[:kanban_board_id])
  end

  def target_stage(params)
    @target_stage ||= target_board(params).kanban_stages.active.find(params[:stage_id])
  end

  def subject(params)
    @subject ||= begin
      rendered = KanbanAutomations::MessagingAction.render_content(
        card: card, content: params[:subject].presence || card.subject.to_s
      )
      raise ArgumentError, 'card subject cannot be blank' if rendered.blank?

      rendered
    end
  end

  def automation_context
    { triggered_by_rule_id: rule.id, automation_depth: context[:automation_depth].to_i + 1 }
  end
end
