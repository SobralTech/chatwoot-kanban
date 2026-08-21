# == Schema Information
#
# Table name: kanban_stages
#
#  id              :bigint           not null, primary key
#  active          :boolean          default(TRUE), not null
#  color           :string           default("#8B8D98"), not null
#  description     :text
#  name            :string           not null
#  position        :integer          default(0), not null
#  sla_hours       :integer
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  kanban_board_id :bigint           not null
#
# Indexes
#
#  index_active_kanban_stages_on_board_id_and_name      (kanban_board_id,name) UNIQUE WHERE (active = true)
#  index_kanban_stages_on_account_id                    (account_id)
#  index_kanban_stages_on_account_id_and_active         (account_id,active)
#  index_kanban_stages_on_kanban_board_id               (kanban_board_id)
#  index_kanban_stages_on_kanban_board_id_and_position  (kanban_board_id,position)
#
class KanbanStage < ApplicationRecord
  SPECIAL_STAGE_ORDER_ERROR = 'special_stages_must_be_last'.freeze
  SPECIAL_STAGE_DELETION_ERROR = 'special_stage_cannot_be_deleted'.freeze

  belongs_to :account
  belongs_to :kanban_board

  has_many :conversation_kanban_states, dependent: :destroy_async
  has_many :kanban_cards, dependent: nil

  validates :account_id, presence: true
  validates :name, presence: true, uniqueness: { scope: :kanban_board_id, conditions: -> { active } }, if: :active?
  validates :position, presence: true, numericality: { only_integer: true }
  validates :color, format: { with: /\A#[0-9A-F]{6}\z/i }
  validates :sla_hours, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :validate_board_account
  validate :validate_special_stage_not_deactivated

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(position: :asc, created_at: :asc, id: :asc) }

  def self.next_active_position(kanban_board)
    special_ids = special_stage_ids(kanban_board)
    stages = kanban_board.kanban_stages.active
    stages = stages.where.not(id: special_ids) if special_ids.present?

    stages.maximum(:position).to_i + 1
  end

  def self.normalize_positions_for_board!(kanban_board)
    transaction do
      lock_reorder_stages_for_board!(kanban_board)

      apply_position_order!(ordered_stages_for_board(kanban_board))
    end
  end

  def self.reposition_special_stages_for_board!(kanban_board, newly_assigned_stage_ids: [])
    transaction do
      lock_reorder_stages_for_board!(kanban_board)

      special_ids = special_stage_ids(kanban_board)
      stages = kanban_board.kanban_stages.active.ordered.to_a
      regular_stages, special_stages = stages.partition { |stage| special_ids.exclude?(stage.id) }
      newly_assigned_stages = special_stages.select { |stage| newly_assigned_stage_ids.include?(stage.id) }
      special_stages -= newly_assigned_stages

      apply_position_order!(regular_stages + special_stages + newly_assigned_stages)
    end
  end

  def self.apply_position_order!(stages)
    stages.each.with_index(1) do |stage, position|
      stage.update!(position: position) if stage.position != position
    end
  end

  def self.shift_active_positions_from!(kanban_board, position)
    kanban_board.kanban_stages.active.where('position >= ?', position).update_all( # rubocop:disable Rails/SkipsModelValidations
      ['position = position + 1, updated_at = ?', Time.current]
    )
  end

  def self.ordered_stages_for_board(kanban_board)
    special_ids = special_stage_ids(kanban_board)
    regular_stages, special_stages = kanban_board.kanban_stages.active.ordered.to_a.partition { |stage| special_ids.exclude?(stage.id) }
    regular_stages + special_stages
  end

  def self.special_stage_ids(kanban_board)
    [kanban_board.won_stage_id, kanban_board.lost_stage_id].compact.uniq
  end

  def self.valid_special_stage_order?(kanban_board, stages)
    special_ids = special_stage_ids(kanban_board)
    special_count = stages.count { |stage| special_ids.include?(stage.id) }

    stages.last(special_count).count { |stage| special_ids.include?(stage.id) } == special_count
  end

  def self.lock_reorder_stages_for_board!(kanban_board)
    where(kanban_board: kanban_board).active.order(:id).lock.each(&:id)
  end

  def total_value
    totals = KanbanCards::Totals.metric(kanban_cards.active)

    BigDecimal(totals.value)
  end

  private

  def validate_board_account
    return if kanban_board.blank? || account_id == kanban_board.account_id

    errors.add(:account_id, :invalid)
  end

  # A board pointing at an inactive won/lost stage cannot be recovered through the API,
  # so the reference has to be moved before the stage can be deactivated.
  def validate_special_stage_not_deactivated
    return if active? || !active_changed?
    return if kanban_board.blank?
    return if self.class.special_stage_ids(kanban_board).exclude?(id)

    errors.add(:active, SPECIAL_STAGE_DELETION_ERROR)
  end
end
