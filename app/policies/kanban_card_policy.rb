class KanbanCardPolicy < ApplicationPolicy
  def show?
    valid_card_scope? && card_access?
  end

  def create?
    show?
  end

  def update?
    show?
  end

  def destroy?
    show?
  end

  def reorder?
    show?
  end

  private

  def valid_card_scope?
    active_runtime_card? && card_account? && board_account? && stage_account? && stage_board? && contact_account? && inbox_account?
  end

  def active_runtime_card?
    record.active? && record.kanban_board&.active? && board_visible_to_user? && record.kanban_stage&.active?
  end

  def board_visible_to_user?
    KanbanBoardPolicy.new(user_context, record.kanban_board).visible?
  end

  def card_account?
    record.account_id == account&.id
  end

  def board_account?
    record.kanban_board&.account_id == account&.id
  end

  def stage_account?
    record.kanban_stage&.account_id == account&.id
  end

  def stage_board?
    record.kanban_stage&.kanban_board_id == record.kanban_board_id
  end

  def contact_account?
    record.contact&.account_id == account&.id
  end

  def inbox_account?
    record.inbox&.account_id == account&.id
  end

  def card_access?
    record.conversation_id.present? ? conversation_card_access? : manual_card_access?
  end

  def conversation_card_access?
    valid_conversation_scope? && ConversationPolicy.new(user_context, record.conversation).show?
  end

  def valid_conversation_scope?
    record.conversation&.account_id == account&.id &&
      record.conversation&.contact_id == record.contact_id &&
      record.conversation&.inbox_id == record.inbox_id
  end

  def manual_card_access?
    administrator? || inbox_access?
  end

  def administrator?
    account_user&.administrator?
  end

  def inbox_access?
    user.inboxes.where(account_id: account&.id).exists?(id: record.inbox_id)
  end
end
