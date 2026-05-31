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
              conditions: -> { where(origin: 'conversation') }
            },
            if: :validate_conversation_uniqueness?
  validate :due_at_after_starts_at
  validate :validate_account_consistency

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(position: :asc, created_at: :asc, id: :asc) }

  def self.normalize_positions_for_stage!(kanban_board:, kanban_stage:)
    transaction do
      stage_active_cards(kanban_board, kanban_stage).lock.each.with_index(1) do |card, position|
        card.update!(position: position) if card.position != position
      end
    end
  end

  def reorder_to_position!(kanban_stage:, position:)
    raise ActiveRecord::RecordNotSaved, 'Inactive kanban cards cannot be reordered' unless active?

    self.class.transaction do
      source_stage = self.kanban_stage
      stage_ids = [source_stage.id, kanban_stage.id].uniq.sort

      self.class.lock_reorder_stages!(stage_ids)
      self.class.lock_active_cards_for_stages!(kanban_board, stage_ids)

      normalize_reorder_stages!(source_stage, kanban_stage)
      reload

      if source_stage == kanban_stage
        reorder_within_stage!(kanban_stage, position)
      else
        reorder_across_stages!(source_stage, kanban_stage, position)
      end

      normalize_reorder_stages!(source_stage, kanban_stage)
      reload
    end
  end

  def self.stage_active_cards(kanban_board, kanban_stage)
    where(kanban_board: kanban_board, kanban_stage: kanban_stage).active.ordered
  end

  def self.lock_reorder_stages!(stage_ids)
    KanbanStage.where(id: stage_ids).order(:id).lock.each(&:id)
  end

  def self.lock_active_cards_for_stages!(kanban_board, stage_ids)
    where(kanban_board: kanban_board, kanban_stage_id: stage_ids).active.order(:kanban_stage_id, :position, :created_at, :id).lock.each(&:id)
  end

  private

  def normalize_reorder_stages!(source_stage, target_stage)
    self.class.normalize_positions_for_stage!(kanban_board: kanban_board, kanban_stage: source_stage)
    return if source_stage == target_stage

    self.class.normalize_positions_for_stage!(kanban_board: kanban_board, kanban_stage: target_stage)
  end

  def reorder_within_stage!(target_stage, target_position)
    cards = stage_active_cards_without_self(target_stage)
    cards.insert(clamped_position(target_position, cards.length + 1) - 1, self)

    update_stage_positions!(cards, target_stage)
  end

  def reorder_across_stages!(source_stage, target_stage, target_position)
    source_cards = stage_active_cards_without_self(source_stage)
    destination_cards = self.class.stage_active_cards(kanban_board, target_stage).to_a

    update_stage_positions!(source_cards, source_stage)

    destination_cards.insert(clamped_position(target_position, destination_cards.length + 1) - 1, self)
    update_stage_positions!(destination_cards, target_stage)
  end

  def stage_active_cards_without_self(stage)
    self.class.stage_active_cards(kanban_board, stage).where.not(id: id).to_a
  end

  def clamped_position(target_position, maximum_position)
    target_position.to_i.clamp(1, maximum_position)
  end

  def update_stage_positions!(cards, target_stage)
    cards.each_with_index do |card, index|
      attributes = changed_position_attributes_for(card, target_stage, index + 1)
      card.update!(attributes) if attributes.present?
    end
  end

  def changed_position_attributes_for(card, target_stage, position)
    attributes = {}
    attributes[:position] = position if card.position != position
    attributes[:kanban_stage] = target_stage if card == self && card.kanban_stage != target_stage
    attributes
  end

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
    conversation? && conversation_id.present?
  end

  def due_at_after_starts_at
    return if starts_at.blank? || due_at.blank? || due_at >= starts_at

    errors.add(:due_at, 'must be greater than or equal to starts at')
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
