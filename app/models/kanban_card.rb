class KanbanCard < ApplicationRecord
  belongs_to :account
  belongs_to :kanban_board
  belongs_to :kanban_stage
  belongs_to :contact
  belongs_to :inbox
  belongs_to :conversation, optional: true

  enum :origin, {
    conversation: 'conversation',
    manual: 'manual'
  }

  before_validation :normalize_manual_subject

  validates :origin, presence: true
  validates :position, presence: true, numericality: { only_integer: true }
  validates :subject, presence: true, if: :manual?
  validates :normalized_subject, presence: true, if: :manual?
  validates :conversation, presence: true, if: :conversation?
  validates :normalized_subject,
            uniqueness: {
              scope: [:kanban_board_id, :contact_id, :inbox_id],
              conditions: -> { where(active: true, origin: 'manual') }
            },
            if: :validate_manual_uniqueness?
  validates :conversation_id,
            uniqueness: {
              scope: :kanban_board_id,
              conditions: -> { where(active: true, origin: 'conversation') }
            },
            if: :validate_conversation_uniqueness?
  validate :validate_account_consistency

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(position: :asc, created_at: :asc, id: :asc) }

  private

  def normalize_manual_subject
    self.normalized_subject = nil
    return unless manual?

    normalized_display_subject = subject.to_s.strip.gsub(/\s+/, ' ')
    self.subject = normalized_display_subject
    self.normalized_subject = normalized_display_subject.presence&.downcase
  end

  def validate_manual_uniqueness?
    active? && manual? && normalized_subject.present?
  end

  def validate_conversation_uniqueness?
    active? && conversation? && conversation_id.present?
  end

  def validate_account_consistency
    validate_account_for(:kanban_board)
    validate_account_for(:kanban_stage)
    validate_account_for(:contact)
    validate_account_for(:inbox)
    validate_account_for(:conversation)
    validate_board_for_stage
    validate_conversation_contact
    validate_conversation_inbox
  end

  def validate_account_for(association_name)
    associated_record = public_send(association_name)
    return if associated_record.blank? || associated_record.account_id == account_id

    errors.add(association_name, :invalid)
  end

  def validate_board_for_stage
    return if kanban_stage.blank? || kanban_board.blank? || kanban_stage.kanban_board_id == kanban_board_id

    errors.add(:kanban_stage, :invalid)
  end

  def validate_conversation_contact
    return if conversation.blank? || contact.blank? || conversation.contact_id == contact_id

    errors.add(:conversation, :invalid)
  end

  def validate_conversation_inbox
    return if conversation.blank? || inbox.blank? || conversation.inbox_id == inbox_id

    errors.add(:conversation, :invalid)
  end
end
