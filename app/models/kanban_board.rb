# == Schema Information
#
# Table name: kanban_boards
#
#  id               :bigint           not null, primary key
#  active           :boolean          default(TRUE), not null
#  description      :text
#  name             :string           not null
#  position         :integer          default(0), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint           not null
#  default_stage_id :bigint
#
# Indexes
#
#  index_active_kanban_boards_on_account_id_and_name  (account_id,name) UNIQUE WHERE (active = true)
#  index_kanban_boards_on_account_id                  (account_id)
#  index_kanban_boards_on_account_id_and_active       (account_id,active)
#  index_kanban_boards_on_account_id_and_position     (account_id,position)
#  index_kanban_boards_on_default_stage_id            (default_stage_id)
#
class KanbanBoard < ApplicationRecord
  belongs_to :account
  belongs_to :default_stage,
             class_name: 'KanbanStage',
             optional: true

  has_many :kanban_stages, dependent: :destroy_async
  has_many :conversation_kanban_states, dependent: :destroy_async

  validates :account_id, presence: true
  validates :name, presence: true, uniqueness: { scope: :account_id, conditions: -> { active } }, if: :active?
  validates :position, presence: true, numericality: { only_integer: true }
  validate :validate_default_stage

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(position: :asc, id: :asc) }

  private

  def validate_default_stage
    return if default_stage.blank?

    errors.add(:default_stage, :invalid) if default_stage.account_id != account_id
    errors.add(:default_stage, :invalid) if default_stage.kanban_board_id != id
    errors.add(:default_stage, :invalid) unless default_stage.active?
  end
end
