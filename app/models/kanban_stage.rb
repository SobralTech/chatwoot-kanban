# == Schema Information
#
# Table name: kanban_stages
#
#  id              :bigint           not null, primary key
#  active          :boolean          default(TRUE), not null
#  color           :string           default("slate"), not null
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

  def self.normalize_positions_for_board!(kanban_board)
    transaction do
      lock_reorder_stages_for_board!(kanban_board)

      kanban_board.kanban_stages.active.ordered.each.with_index(1) do |stage, position|
        stage.update!(position: position) if stage.position != position
      end
    end
  end

  def self.lock_reorder_stages_for_board!(kanban_board)
    where(kanban_board: kanban_board).active.order(:id).lock.each(&:id)
  end

  private

  def validate_board_account
    return if kanban_board.blank? || account_id == kanban_board.account_id

    errors.add(:account_id, :invalid)
  end
end
