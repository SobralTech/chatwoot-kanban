# == Schema Information
#
# Table name: kanban_custom_fields
#
#  id              :bigint           not null, primary key
#  active          :boolean          default(TRUE), not null
#  field_type      :integer          default("text"), not null
#  key             :string           not null
#  multiple        :boolean          default(FALSE), not null
#  position        :integer          default(0), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  kanban_board_id :bigint           not null
#
# Indexes
#
#  index_active_kanban_custom_fields_on_board_id_and_key  (kanban_board_id,key) UNIQUE WHERE (active = true)
#  index_kanban_custom_fields_on_account_id               (account_id)
#  index_kanban_custom_fields_on_kanban_board_id          (kanban_board_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (kanban_board_id => kanban_boards.id)
#
class KanbanCustomField < ApplicationRecord
  belongs_to :account
  belongs_to :kanban_board

  has_many :kanban_card_field_values, dependent: :destroy

  enum :field_type, { text: 0, number: 1, date: 2, boolean: 3 }

  validates :key, presence: true, uniqueness: { scope: :kanban_board_id, conditions: -> { active } }, if: :active?
  validates :field_type, presence: true
  validate :validate_account_consistency

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(position: :asc, id: :asc) }

  private

  def validate_account_consistency
    return if kanban_board.blank? || account_id == kanban_board.account_id

    errors.add(:account_id, :invalid)
  end
end
