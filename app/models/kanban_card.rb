# rubocop:disable Metrics/ClassLength
# rubocop:disable Layout/LineLength
# == Schema Information
#
# Table name: kanban_cards
#
#  id                     :bigint           not null, primary key
#  active                 :boolean          default(TRUE), not null
#  description            :text
#  discount_amount        :decimal(12, 2)
#  discount_type          :integer          default("percent"), not null
#  due_at                 :datetime
#  normalized_subject     :string
#  origin                 :string           not null
#  position               :integer          default(0), not null
#  priority               :integer
#  stage_entered_at       :datetime         not null
#  starts_at              :datetime
#  subject                :string
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  account_id             :bigint           not null
#  contact_id             :bigint           not null
#  conversation_id        :bigint
#  inbox_id               :bigint           not null
#  kanban_board_id        :bigint           not null
#  kanban_reason_id       :bigint
#  kanban_stage_id        :bigint           not null
#  previous_stage_id      :bigint
#  recreated_from_card_id :bigint
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
#  index_kanban_cards_on_kanban_reason_id             (kanban_reason_id)
#  index_kanban_cards_on_previous_stage_id            (previous_stage_id)
#  index_kanban_cards_on_recreated_from_card_id       (recreated_from_card_id)
#  index_kanban_cards_on_subject_trgm                 (immutable_unaccent(lower((subject)::text)) gin_trgm_ops) WHERE (active = true) USING gin
#
# Foreign Keys
#
#  fk_rails_...  (previous_stage_id => kanban_stages.id) ON DELETE => nullify
#  fk_rails_...  (recreated_from_card_id => kanban_cards.id) ON DELETE => nullify
#
# rubocop:enable Layout/LineLength
class KanbanCard < ApplicationRecord
  include Labelable

  belongs_to :account
  belongs_to :kanban_board
  belongs_to :kanban_stage
  belongs_to :previous_stage, class_name: 'KanbanStage', optional: true, inverse_of: false
  belongs_to :contact
  belongs_to :inbox
  belongs_to :conversation, optional: true
  belongs_to :kanban_reason, optional: true
  belongs_to :recreated_from_card, class_name: 'KanbanCard', optional: true, inverse_of: false

  has_many :kanban_card_assignees, dependent: :destroy
  has_many :assignees, through: :kanban_card_assignees, source: :user
  has_many :kanban_card_products, dependent: :destroy
  has_many :kanban_card_field_values, dependent: :destroy
  has_many :kanban_card_events, dependent: :delete_all
  has_many :kanban_card_notes, dependent: :destroy
  has_many :kanban_automation_logs, dependent: :nullify

  enum :origin, {
    conversation: 'conversation',
    manual: 'manual'
  }

  enum :priority, { low: 0, medium: 1, high: 2, urgent: 3 }
  enum :discount_type, { percent: 0, amount: 1 }, prefix: true

  # Positions are sparse: the active cards of a stage sit POSITION_GAP apart, so dropping a
  # card between two neighbours is one row written instead of the whole stage renumbered.
  # The gap only runs out after roughly ten drops into the very same slot.
  POSITION_GAP = 1000

  SORT_ORDER_SQL = {
    'created_at_desc' => 'kanban_cards.created_at DESC, kanban_cards.id DESC',
    'created_at_asc' => 'kanban_cards.created_at ASC, kanban_cards.id ASC',
    'name_asc' => "COALESCE(NULLIF(kanban_cards.subject, ''), contacts.name) ASC NULLS LAST, kanban_cards.id ASC"
  }.freeze

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
              conditions: -> { where(active: true, origin: 'conversation').where.not(normalized_subject: nil) }
            },
            if: :validate_conversation_uniqueness?
  validate :due_at_after_starts_at
  validate :validate_account_consistency

  validates :discount_amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :discount_amount, numericality: { less_than_or_equal_to: 100 }, allow_nil: true, if: :discount_type_percent?

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(position: :asc, created_at: :asc, id: :asc) }
  scope :active_non_terminal_for, lambda { |kanban_board, contact_id|
    active.where(kanban_board: kanban_board, contact_id: contact_id)
          .where.not(kanban_stage_id: KanbanStage.special_stage_ids(kanban_board))
  }

  def items_total
    kanban_card_products.sum { |product| product.unit_price * product.quantity }
  end

  # A percentage is relative to the items, an amount is already absolute. The card
  # keeps whichever the user picked so nothing has to be inferred from a null column.
  def discount_value
    return BigDecimal(0) if discount_amount.blank?
    return items_total * (discount_amount / 100) if discount_type_percent?

    discount_amount
  end

  def total_value
    [items_total - discount_value, 0].max
  end

  # A card mirrored from a conversation by the board sync carries no subject of its own,
  # so the surfaces that need a title fall back to the contact and the inbox.
  def self.default_subject_for(contact:, inbox:)
    contact_name = contact.name.presence || "Contact ##{contact.id}"
    inbox_name = inbox.name.presence || "Inbox ##{inbox.id}"
    "#{contact_name} - #{inbox_name}"
  end

  def display_subject
    subject.presence || self.class.default_subject_for(contact: contact, inbox: inbox)
  end

  def self.normalize_positions_for_stage!(kanban_board:, kanban_stage:)
    transaction do
      stage_active_cards(kanban_board, kanban_stage).lock.pluck(:id)
      bulk_normalize_positions_for_stage!(kanban_board, kanban_stage)
    end
  end

  # Where a card lands when it is dropped right after `after_card`, or at the top of the
  # stage when that is nil. The stage row is locked so two drops into the same slot cannot
  # settle on the same midpoint; the caller keeps that lock by wrapping this and the move
  # that follows in one transaction. A slot with no integer left between its neighbours
  # rebalances the stage first, which is the only path that writes more than one row.
  def self.drop_position(kanban_board:, kanban_stage:, after_card: nil, moved_card: nil)
    transaction do
      lock_reorder_stages!([kanban_stage.id])

      slot_position(kanban_board, kanban_stage, after_card, moved_card) || begin
        normalize_positions_for_stage!(kanban_board: kanban_board, kanban_stage: kanban_stage)
        slot_position(kanban_board, kanban_stage, after_card&.reload, moved_card)
      end
    end
  end

  # Past the last active card of the stage: where an appended card goes.
  def self.end_position(kanban_board:, kanban_stage:)
    stage_active_cards(kanban_board, kanban_stage).maximum(:position).to_i + POSITION_GAP
  end

  # Ahead of the first active card of the stage: where a newly created card goes, without
  # the rest of the stage having to shift out of its way.
  def self.top_position(kanban_board:, kanban_stage:)
    drop_position(kanban_board: kanban_board, kanban_stage: kanban_stage)
  end

  # A move rewrites a single row: the card takes the position the caller resolved and, when
  # it changed stage, restarts its stage clock. Both stage rows are locked in id order so
  # two moves over the same pair cannot deadlock.
  def reorder_to_position!(kanban_stage:, position:)
    raise ActiveRecord::RecordNotSaved, 'Inactive kanban cards cannot be reordered' unless active?

    self.class.transaction do
      self.class.lock_reorder_stages!([kanban_stage_id, kanban_stage.id].uniq.sort)

      # rubocop:disable Rails/SkipsModelValidations
      update_columns(moved_card_attributes(kanban_stage, position))
      # rubocop:enable Rails/SkipsModelValidations
      reload
    end
  end

  def update_assignees!(user_ids)
    target_ids = Array(user_ids).filter_map(&:presence).map(&:to_i).uniq

    self.class.transaction do
      kanban_card_assignees.where.not(user_id: target_ids).destroy_all
      (target_ids - kanban_card_assignees.pluck(:user_id)).each do |user_id|
        kanban_card_assignees.create!(account: account, user_id: user_id)
      end
    end
  end

  def deactivate_and_normalize!
    self.class.transaction do
      stage = kanban_stage

      self.class.lock_reorder_stages!([stage.id])
      self.class.lock_active_cards_for_stages!(kanban_board, [stage.id])

      destroy!
      self.class.normalize_positions_for_stage!(kanban_board: kanban_board, kanban_stage: stage)
    end
  end

  def self.stage_active_cards(kanban_board, kanban_stage)
    where(kanban_board: kanban_board, kanban_stage: kanban_stage).active.ordered
  end

  def self.lock_reorder_stages!(stage_ids)
    KanbanStage.where(id: stage_ids).order(:id).lock.each(&:id)
  end

  # The card being moved is skipped: it is either leaving the slot it occupies or arriving
  # from another stage, so it never counts as its own neighbour.
  def self.slot_position(kanban_board, kanban_stage, after_card, moved_card)
    scope = stage_active_cards(kanban_board, kanban_stage)
    scope = scope.where.not(id: moved_card.id) if moved_card&.id

    before = after_card&.position
    after = before ? scope.where(position: (before + 1)..).pick(:position) : scope.pick(:position)

    position_between(before, after)
  end

  # nil when the neighbours have no integer left between them, which is the signal to
  # rebalance the stage before placing the card.
  def self.position_between(before, after)
    return POSITION_GAP if before.nil? && after.nil?
    return after - POSITION_GAP if before.nil?
    return before + POSITION_GAP if after.nil?
    return nil if after - before < 2

    before + ((after - before) / 2)
  end

  # A stage has no size limit, so the lock plucks ids rather than instantiating a record per
  # card. The ordering is what keeps concurrent callers from deadlocking, not the rows.
  def self.lock_active_cards_for_stages!(kanban_board, stage_ids)
    where(kanban_board: kanban_board, kanban_stage_id: stage_ids).active.order(:kanban_stage_id, :position, :created_at, :id).lock.pluck(:id)
  end

  def self.bulk_normalize_positions_for_stage!(kanban_board, kanban_stage)
    connection.execute(<<~SQL.squish)
      WITH ordered_cards AS (
        SELECT id, row_number() OVER (ORDER BY position ASC, created_at ASC, id ASC) * #{POSITION_GAP} AS normalized_position
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

  def self.sort_active_cards_for_stage!(kanban_board:, kanban_stage:, sort_by:)
    transaction do
      lock_reorder_stages!([kanban_stage.id])
      lock_active_cards_for_stages!(kanban_board, [kanban_stage.id])
      bulk_sort_active_cards_for_stage!(kanban_board, kanban_stage, sort_by)
    end
  end

  # The whole source stage lands past the last card of the target, so neither stage needs
  # renumbering: the source is left empty and the target keeps the gaps it already had.
  def self.move_active_cards_to_stage!(kanban_board:, source_stage:, target_stage:)
    transaction do
      stage_ids = [source_stage.id, target_stage.id].sort
      lock_reorder_stages!(stage_ids)
      lock_active_cards_for_stages!(kanban_board, stage_ids)

      target_last_position = stage_active_cards(kanban_board, target_stage).maximum(:position).to_i
      bulk_move_active_cards!(kanban_board, source_stage, target_stage, target_last_position)
    end
  end

  def self.bulk_sort_active_cards_for_stage!(kanban_board, kanban_stage, sort_by)
    order_sql = SORT_ORDER_SQL.fetch(sort_by)

    connection.execute(<<~SQL.squish)
      WITH ordered_cards AS (
        SELECT kanban_cards.id, row_number() OVER (ORDER BY #{order_sql}) * #{POSITION_GAP} AS sorted_position
        FROM #{quoted_table_name}
        LEFT JOIN #{Contact.quoted_table_name} ON #{Contact.quoted_table_name}.id = #{quoted_table_name}.contact_id
        WHERE #{quoted_table_name}.kanban_board_id = #{connection.quote(kanban_board.id)}
          AND #{quoted_table_name}.kanban_stage_id = #{connection.quote(kanban_stage.id)}
          AND #{quoted_table_name}.active = TRUE
      )
      UPDATE #{quoted_table_name}
      SET position = ordered_cards.sorted_position,
          updated_at = #{connection.quote(Time.current)}
      FROM ordered_cards
      WHERE #{quoted_table_name}.id = ordered_cards.id
        AND #{quoted_table_name}.position != ordered_cards.sorted_position
    SQL
  end

  def self.bulk_move_active_cards!(kanban_board, source_stage, target_stage, target_last_position)
    current_time = connection.quote(Time.current)

    connection.execute(<<~SQL.squish)
      WITH source_cards AS (
        SELECT id, row_number() OVER (ORDER BY position ASC, created_at ASC, id ASC) * #{POSITION_GAP} + #{target_last_position} AS target_position
        FROM #{quoted_table_name}
        WHERE kanban_board_id = #{connection.quote(kanban_board.id)}
          AND kanban_stage_id = #{connection.quote(source_stage.id)}
          AND active = TRUE
      )
      UPDATE #{quoted_table_name}
      SET kanban_stage_id = #{connection.quote(target_stage.id)},
          position = source_cards.target_position,
          kanban_reason_id = NULL,
          previous_stage_id = NULL,
          stage_entered_at = #{current_time},
          updated_at = #{current_time}
      FROM source_cards
      WHERE #{quoted_table_name}.id = source_cards.id
    SQL
  end

  private_class_method :slot_position, :position_between,
                       :bulk_normalize_positions_for_stage!, :bulk_sort_active_cards_for_stage!, :bulk_move_active_cards!

  private

  def moved_card_attributes(target_stage, position)
    attributes = { position: position.to_i, updated_at: Time.current }
    return attributes if kanban_stage_id == target_stage.id

    attributes.merge(kanban_stage_id: target_stage.id, stage_entered_at: Time.current)
  end

  def normalize_subject
    self.normalized_subject = nil

    normalized_display_subject = subject.to_s.strip.gsub(/\s+/, ' ')
    self.subject = normalized_display_subject.presence
    self.normalized_subject = normalized_display_subject.presence&.downcase if recreated_from_card_id.blank?
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
    validate_account_for(:kanban_reason)
    validate_account_for(:recreated_from_card)
    validate_board_for_stage
    validate_board_for_reason
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

  def validate_board_for_reason
    return if kanban_reason.blank? || kanban_board.blank? || kanban_reason.kanban_board_id == kanban_board_id

    errors.add(:kanban_reason, :invalid)
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
