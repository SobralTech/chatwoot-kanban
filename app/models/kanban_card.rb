# rubocop:disable Metrics/ClassLength
# rubocop:disable Layout/LineLength
# == Schema Information
#
# Table name: kanban_cards
#
#  id                 :bigint           not null, primary key
#  active             :boolean          default(TRUE), not null
#  description        :text
#  due_at             :datetime
#  normalized_subject :string
#  origin             :string           not null
#  position           :integer          default(0), not null
#  stage_entered_at   :datetime         not null
#  starts_at          :datetime
#  subject            :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  contact_id         :bigint           not null
#  conversation_id    :bigint
#  inbox_id           :bigint           not null
#  kanban_board_id    :bigint           not null
#  kanban_stage_id    :bigint           not null
#
# Indexes
#
#  index_active_kanban_cards_on_board_stage_order     (kanban_board_id,kanban_stage_id,position,created_at,id) WHERE (active = true)
#  index_active_manual_kanban_cards_unique_subject    (kanban_board_id,contact_id,inbox_id,normalized_subject) UNIQUE WHERE ((active = true) AND ((origin)::text = 'manual'::text) AND (normalized_subject IS NOT NULL))
#  index_kanban_cards_on_account_id_and_active        (account_id,active)
#  index_kanban_cards_on_account_id_and_contact_id    (account_id,contact_id)
#  index_kanban_cards_on_account_id_and_inbox_id      (account_id,inbox_id)
#  index_kanban_cards_on_board_stage_position         (kanban_board_id,kanban_stage_id,position)
#  index_kanban_cards_on_conversation_id              (conversation_id)
#  index_kanban_cards_on_conversation_subject_unique  (kanban_board_id,conversation_id,inbox_id,normalized_subject) UNIQUE WHERE (((origin)::text = 'conversation'::text) AND (conversation_id IS NOT NULL) AND (normalized_subject IS NOT NULL))
#  index_kanban_cards_on_kanban_board_id_and_active   (kanban_board_id,active)
#
# rubocop:enable Layout/LineLength
class KanbanCard < ApplicationRecord
  include Labelable

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

  before_validation :normalize_subject
  before_validation :normalize_blank_description
  before_validation :set_stage_entered_at, if: :stage_entry_timestamp_required?

  validates :origin, presence: true
  validates :position, presence: true, numericality: { only_integer: true }
  validates :stage_entered_at, presence: true
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
              scope: [:kanban_board_id, :inbox_id, :normalized_subject],
              conditions: -> { where(origin: 'conversation').where.not(normalized_subject: nil) }
            },
            if: :validate_conversation_uniqueness?
  validate :due_at_after_starts_at
  validate :validate_account_consistency

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(position: :asc, created_at: :asc, id: :asc) }

  def self.normalize_positions_for_stage!(kanban_board:, kanban_stage:)
    transaction do
      stage_active_cards(kanban_board, kanban_stage).lock.pluck(:id)
      bulk_normalize_positions_for_stage!(kanban_board, kanban_stage)
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

  def deactivate_and_normalize!
    self.class.transaction do
      stage = kanban_stage

      self.class.lock_reorder_stages!([stage.id])
      self.class.lock_active_cards_for_stages!(kanban_board, [stage.id])

      self.class.where(id: id).update_all(active: false, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      self.class.normalize_positions_for_stage!(kanban_board: kanban_board, kanban_stage: stage)
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

  def self.bulk_normalize_positions_for_stage!(kanban_board, kanban_stage)
    connection.execute(<<~SQL.squish)
      WITH ordered_cards AS (
        SELECT id, row_number() OVER (ORDER BY position ASC, created_at ASC, id ASC) AS normalized_position
        FROM #{quoted_table_name}
        WHERE kanban_board_id = #{connection.quote(kanban_board.id)}
          AND kanban_stage_id = #{connection.quote(kanban_stage.id)}
          AND active = TRUE
      )
      UPDATE #{quoted_table_name}
      SET position = ordered_cards.normalized_position,
          updated_at = #{connection.quote(Time.current)}
      FROM ordered_cards
      WHERE #{quoted_table_name}.id = ordered_cards.id
        AND #{quoted_table_name}.position != ordered_cards.normalized_position
    SQL
  end

  private_class_method :bulk_normalize_positions_for_stage!

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
    changed_cards = cards.each_with_index.filter_map do |card, index|
      position = index + 1
      next if card.position == position && card.kanban_stage_id == target_stage.id

      [card.id, position, card.kanban_stage_id != target_stage.id]
    end

    return if changed_cards.blank?

    # rubocop:disable Rails/SkipsModelValidations
    self.class.where(id: changed_cards.map(&:first)).update_all(bulk_position_update_sql(changed_cards, target_stage))
    # rubocop:enable Rails/SkipsModelValidations
  end

  def bulk_position_update_sql(changed_cards, target_stage)
    current_time = self.class.connection.quote(Time.current)
    position_cases = changed_cards.map { |card_id, position, _stage_changed| "WHEN #{card_id} THEN #{position}" }.join(' ')
    stage_cases = changed_cards.map { |card_id, _position, _stage_changed| "WHEN #{card_id} THEN #{target_stage.id}" }.join(' ')
    stage_entered_at_cases = changed_cards.filter_map do |card_id, _position, stage_changed|
      "WHEN #{card_id} THEN #{current_time}" if stage_changed
    end.join(' ')

    <<~SQL.squish
      position = CASE id #{position_cases} ELSE position END,
      kanban_stage_id = CASE id #{stage_cases} ELSE kanban_stage_id END,
      #{stage_entered_at_update_sql(stage_entered_at_cases)}
      updated_at = #{current_time}
    SQL
  end

  def stage_entered_at_update_sql(stage_entered_at_cases)
    return 'stage_entered_at = stage_entered_at,' if stage_entered_at_cases.blank?

    "stage_entered_at = CASE id #{stage_entered_at_cases} ELSE stage_entered_at END,"
  end

  def normalize_subject
    self.normalized_subject = nil

    normalized_display_subject = subject.to_s.strip.gsub(/\s+/, ' ')
    self.subject = normalized_display_subject.presence
    self.normalized_subject = normalized_display_subject.presence&.downcase
  end

  def normalize_blank_description
    self.description = nil if description.blank?
  end

  def stage_entry_timestamp_required?
    new_record? || will_save_change_to_kanban_stage_id?
  end

  def set_stage_entered_at
    self.stage_entered_at = Time.current
  end

  def validate_manual_uniqueness?
    active? && manual? && normalized_subject.present?
  end

  def validate_conversation_uniqueness?
    conversation? && conversation_id.present? && normalized_subject.present?
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
# rubocop:enable Metrics/ClassLength
