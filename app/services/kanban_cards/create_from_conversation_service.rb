class KanbanCards::CreateFromConversationService
  DUPLICATE_CONVERSATION_ERROR = 'Conversation already has an opportunity with this subject on this board'.freeze

  # rubocop:disable Metrics/ParameterLists
  def initialize(account:, user:, conversation:, kanban_board:, kanban_stage:, subject:, due_at: nil, labels: [])
    @account = account
    @user = user
    @conversation = conversation
    @kanban_board = kanban_board
    @kanban_stage = kanban_stage
    @subject = subject
    @due_at = due_at
    @labels = labels
  end
  # rubocop:enable Metrics/ParameterLists

  def perform!
    validate_scope!

    card = KanbanCard.transaction do
      kanban_stage.lock!
      lock_active_cards!
      shift_active_cards_down!
      create_card!.tap { |created_card| created_card.update_labels(label_titles) }
    end
    dispatch_card_created_event(card)
    card
  rescue ActiveRecord::RecordNotUnique
    raise_validation_error(DUPLICATE_CONVERSATION_ERROR, :conversation)
  end

  private

  attr_reader :account, :user, :conversation, :kanban_board, :kanban_stage, :subject, :due_at, :labels

  def validate_scope!
    validate_conversation!
    validate_board!
    validate_stage!
    validate_duplicate!
    validate_labels!
    authorize_card!
  end

  def validate_conversation!
    raise_validation_error('Conversation must belong to account', :conversation) unless conversation.account_id == account.id
    raise_validation_error('Conversation must have a contact', :conversation) if conversation.contact_id.blank?
    raise_validation_error('Conversation must have an inbox', :conversation) if conversation.inbox_id.blank?
    raise Pundit::NotAuthorizedError unless ConversationPolicy.new(user_context, conversation).show?
  end

  def validate_board!
    raise_validation_error('Board must belong to account', :kanban_board) unless kanban_board.account_id == account.id
    raise_validation_error('Board must be active', :kanban_board) unless kanban_board.active?
    raise Pundit::NotAuthorizedError unless KanbanBoardPolicy.new(user_context, kanban_board).visible?

    return if kanban_board.inbox_allowed?(conversation.inbox_id)

    raise_validation_error('Conversation inbox is not allowed by board scope',
                           :conversation)
  end

  def validate_stage!
    raise_validation_error('Stage must belong to board', :kanban_stage) unless kanban_stage.kanban_board_id == kanban_board.id
    raise_validation_error('Stage must be active', :kanban_stage) unless kanban_stage.active?
  end

  def validate_duplicate!
    return unless KanbanCard.conversation.exists?(
      kanban_board: kanban_board,
      conversation_id: conversation.id,
      inbox_id: conversation.inbox_id,
      normalized_subject: normalized_card_subject.downcase
    )

    raise_validation_error(DUPLICATE_CONVERSATION_ERROR, :conversation)
  end

  def validate_labels!
    return if label_titles.blank?
    return if existing_label_titles.sort == label_titles.sort

    raise_validation_error('Labels must exist in account', :labels)
  end

  def authorize_card!
    raise Pundit::NotAuthorizedError unless KanbanCardPolicy.new(user_context, unsaved_card).create?
  end

  def create_card!
    KanbanCard.create!(card_attributes)
  end

  def card_attributes
    {
      account: account,
      kanban_board: kanban_board,
      kanban_stage: kanban_stage,
      contact: conversation.contact,
      inbox: conversation.inbox,
      conversation: conversation,
      subject: normalized_card_subject,
      origin: 'conversation',
      position: 1,
      due_at: due_at,
      active: true
    }
  end

  def unsaved_card
    @unsaved_card ||= KanbanCard.new(card_attributes)
  end

  def dispatch_card_created_event(card)
    Rails.configuration.dispatcher.dispatch(
      Events::Types::KANBAN_CARD_CREATED,
      Time.zone.now,
      account_id: card.account_id,
      board_id: card.kanban_board_id,
      stage_id: card.kanban_stage_id,
      card_id: card.id,
      conversation_id: card.conversation_id
    )
  end

  def lock_active_cards!
    KanbanCard.lock_active_cards_for_stages!(kanban_board, [kanban_stage.id])
  end

  def shift_active_cards_down!
    KanbanCard.where(kanban_board: kanban_board, kanban_stage: kanban_stage).active.update_all( # rubocop:disable Rails/SkipsModelValidations
      ['position = position + 1, updated_at = ?', Time.current]
    )
  end

  def normalized_subject
    @normalized_subject ||= normalize_subject(subject)
  end

  def normalized_card_subject
    @normalized_card_subject ||= normalized_subject.presence || normalize_subject(default_subject)
  end

  def normalize_subject(value)
    value.to_s.strip.gsub(/\s+/, ' ')
  end

  def label_titles
    @label_titles ||= Array(labels).filter_map { |label| label.to_s.strip.presence }.uniq
  end

  def existing_label_titles
    @existing_label_titles ||= account.labels.where(title: label_titles).pluck(:title)
  end

  def default_subject
    "#{contact_display_name} - #{inbox_display_name}"
  end

  def contact_display_name
    conversation.contact.name.presence || "Contact ##{conversation.contact_id}"
  end

  def inbox_display_name
    conversation.inbox.name.presence || "Inbox ##{conversation.inbox_id}"
  end

  def user_context
    @user_context ||= { user: user, account: account, account_user: account_user }
  end

  def account_user
    @account_user ||= user.account_users.find_by(account: account)
  end

  def raise_validation_error(message, attribute = :base)
    card = KanbanCard.new
    card.errors.add(attribute, message)
    raise ActiveRecord::RecordInvalid, card
  end
end
