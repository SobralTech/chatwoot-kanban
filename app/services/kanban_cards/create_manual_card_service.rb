class KanbanCards::CreateManualCardService
  DUPLICATE_SUBJECT_ERROR = 'Manual opportunity with this subject already exists for this contact and inbox'.freeze

  # rubocop:disable Metrics/ParameterLists
  def initialize(account:, user:, kanban_board:, kanban_stage:, contact:, inbox:, subject:, conversation: nil, context: {})
    @account = account
    @user = user
    @kanban_board = kanban_board
    @kanban_stage = kanban_stage
    @contact = contact
    @inbox = inbox
    @subject = subject
    @conversation = conversation
    @context = context.to_h.with_indifferent_access
  end
  # rubocop:enable Metrics/ParameterLists

  def perform!
    validate_scope!

    card = KanbanCard.transaction do
      kanban_stage.lock!
      create_card!.tap do |created_card|
        KanbanCards::RecordEventService.card_created(created_card, user: user)
      end
    end
    dispatch_card_created_event(card)
    trigger_automation(card)
    card
  rescue ActiveRecord::RecordNotUnique
    raise_validation_error(DUPLICATE_SUBJECT_ERROR, :subject)
  end

  private

  attr_reader :account, :user, :kanban_board, :kanban_stage, :contact, :inbox, :subject, :conversation, :context

  def validate_scope!
    validate_board!
    validate_stage!
    validate_records!
    validate_conversation!
    validate_subject!
  end

  def validate_board!
    raise_validation_error('Board must belong to account', :kanban_board) unless kanban_board.account_id == account.id
    raise_validation_error('Board must be active', :kanban_board) unless kanban_board.active?
    return if system_run?

    raise Pundit::NotAuthorizedError unless KanbanBoardPolicy.new(user_context, kanban_board).visible?
  end

  def validate_stage!
    raise_validation_error('Stage must belong to board', :kanban_stage) unless kanban_stage.kanban_board_id == kanban_board.id
    raise_validation_error('Stage must be active', :kanban_stage) unless kanban_stage.active?
  end

  def validate_records!
    raise_validation_error('Contact must belong to account', :contact) unless contact.account_id == account.id
    raise_validation_error('Inbox must belong to account', :inbox) unless inbox.account_id == account.id
    raise_validation_error('User cannot access inbox', :inbox) unless system_run? || user_can_access_inbox?
    raise_validation_error('Inbox is not allowed by board scope', :inbox) unless kanban_board.inbox_allowed?(inbox)
  end

  def validate_conversation!
    return unless conversation

    raise_validation_error('Conversation must belong to account', :conversation) unless conversation.account_id == account.id
    raise_validation_error('Conversation must belong to contact', :conversation) unless conversation.contact_id == contact.id
    raise_validation_error('Conversation must use selected inbox', :conversation) unless conversation.inbox_id == inbox.id
    return if system_run?

    raise_validation_error('User cannot access conversation', :conversation) unless ConversationPolicy.new(user_context, conversation).show?
  end

  def validate_subject!
    raise_validation_error("Subject can't be blank", :subject) if normalized_subject.blank?
    raise_validation_error(DUPLICATE_SUBJECT_ERROR, :subject) if duplicate_subject?
  end

  def create_card!
    KanbanCard.create!(
      account: account,
      kanban_board: kanban_board,
      kanban_stage: kanban_stage,
      contact: contact,
      inbox: inbox,
      conversation: card_conversation,
      subject: normalized_subject,
      origin: 'manual',
      position: KanbanCard.top_position(kanban_board: kanban_board, kanban_stage: kanban_stage),
      active: true
    )
  end

  def dispatch_card_created_event(card)
    KanbanCards::EventDispatcher.card_event(Events::Types::KANBAN_CARD_CREATED, card)
  end

  def duplicate_subject?
    KanbanCard.manual.active.exists?(
      kanban_board: kanban_board,
      contact: contact,
      inbox: inbox,
      normalized_subject: normalized_subject.downcase
    )
  end

  def normalized_subject
    @normalized_subject ||= subject.to_s.strip.gsub(/\s+/, ' ')
  end

  def card_conversation
    conversation || permitted_conversation
  end

  def permitted_conversation
    return if system_run?

    @permitted_conversation ||= matching_conversations.find do |matching_conversation|
      ConversationPolicy.new(user_context, matching_conversation).show?
    end
  end

  def matching_conversations
    Conversation.where(account_id: account.id, contact_id: contact.id, inbox_id: inbox.id).order(last_activity_at: :desc, id: :desc)
  end

  def user_can_access_inbox?
    administrator? || user&.inboxes&.where(account_id: account.id)&.exists?(id: inbox.id)
  end

  def administrator?
    account_user&.administrator?
  end

  # No user means the automation engine is acting as the system, so there is no agent
  # whose permissions could be checked.
  def system_run?
    user.nil?
  end

  def user_context
    @user_context ||= { user: user, account: account, account_user: account_user }
  end

  def account_user
    @account_user ||= user&.account_users&.find_by(account: account)
  end

  def trigger_automation(card)
    KanbanAutomations::TriggerService.call(
      card: card,
      event_name: 'card_created',
      user: user,
      context: context
    )
  end

  def raise_validation_error(message, attribute = :base)
    card = KanbanCard.new
    card.errors.add(attribute, message)
    raise ActiveRecord::RecordInvalid, card
  end
end
