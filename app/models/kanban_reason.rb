# == Schema Information
#
# Table name: kanban_reasons
#
#  id              :bigint           not null, primary key
#  active          :boolean          default(TRUE), not null
#  description     :text
#  position        :integer          default(0), not null
#  reason_type     :integer          default("lost"), not null
#  title           :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  kanban_board_id :bigint           not null
#
# Indexes
#
#  index_kanban_reasons_on_account_id       (account_id)
#  index_kanban_reasons_on_kanban_board_id  (kanban_board_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (kanban_board_id => kanban_boards.id)
#
class KanbanReason < ApplicationRecord
  belongs_to :account
  belongs_to :kanban_board

  enum :reason_type, { lost: 0, won: 1 }

  validates :title, presence: true
  validates :reason_type, presence: true
  validate :validate_account_consistency

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(position: :asc, id: :asc) }

  private

  def validate_account_consistency
    return if kanban_board.blank? || account_id == kanban_board.account_id

    errors.add(:account_id, :invalid)
  end
end
