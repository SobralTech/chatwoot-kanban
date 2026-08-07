# == Schema Information
#
# Table name: kanban_stages
#
#  id              :bigint           not null, primary key
#  active          :boolean          default(TRUE), not null
#  color           :string           default("slate"), not null
#  description     :text
#  name            :string           not null
#  position        :integer          default(0), not null
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

  belongs_to :account
  belongs_to :kanban_board

  has_many :conversation_kanban_states, dependent: :destroy_async
  has_many :kanban_cards, dependent: nil

  validates :account_id, presence: true
  validates :name, presence: true, uniqueness: { scope: :kanban_board_id, conditions: -> { active } }, if: :active?
  validates :position, presence: true, numericality: { only_integer: true }
  validate :validate_board_account

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(position: :asc, created_at: :asc, id: :asc) }

  def self.next_active_position(kanban_board)
    return 1 if special_stage_ids(kanban_board).blank?

    kanban_board.kanban_stages.active.where.not(id: special_stage_ids(kanban_board)).maximum(:position).to_i + 1
  end

  def self.normalize_positions_for_board!(kanban_board)
    transaction do
      lock_reorder_stages_for_board!(kanban_board)

      ordered_stages_for_board(kanban_board).each.with_index(1) do |stage, position|
        stage.update!(position: position) if stage.position != position
      end
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

      (regular_stages + special_stages + newly_assigned_stages).each.with_index(1) do |stage, position|
        stage.update!(position: position) if stage.position != position
      end
    end
  end

  def self.shift_active_positions_from!(kanban_board, position)
    kanban_board.kanban_stages.active.where('position >= ?', position).update_all( # rubocop:disable Rails/SkipsModelValidations
      ['position = position + 1, updated_at = ?', Time.current]
    )
  end

  def self.ordered_stages_for_board(kanban_board)
    special_ids = special_stage_ids(kanban_board)
    kanban_board.kanban_stages.active.ordered.to_a.partition { |stage| special_ids.exclude?(stage.id) }.flatten
  end

  def self.special_stage_ids(kanban_board)
    [kanban_board.won_stage_id, kanban_board.lost_stage_id].compact.uniq
  end

  def self.valid_special_stage_order?(kanban_board, stages)
    special_ids = special_stage_ids(kanban_board)
    special_count = stages.count { |stage| special_ids.include?(stage.id) }
    return true if special_count.zero?

    stages.each_with_index.none? do |stage, index|
      special_ids.include?(stage.id) && index < stages.length - special_count
    end
  end

  def self.lock_reorder_stages_for_board!(kanban_board)
    where(kanban_board: kanban_board).active.order(:id).lock.each(&:id)
  end

  def total_value
    KanbanCardProduct.joins(:kanban_card)
                     .merge(KanbanCard.active)
                     .where(kanban_cards: { kanban_stage_id: id })
                     .sum('kanban_card_products.unit_price * kanban_card_products.quantity')
  end

  private

  def validate_board_account
    return if kanban_board.blank? || account_id == kanban_board.account_id

    errors.add(:account_id, :invalid)
  end
end
