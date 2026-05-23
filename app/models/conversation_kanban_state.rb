# == Schema Information
#
# Table name: conversation_kanban_states
#
#  id              :bigint           not null, primary key
#  moved_at        :datetime
#  position        :integer          default(0), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  conversation_id :bigint           not null
#  kanban_board_id :bigint           not null
#  kanban_stage_id :bigint           not null
#  moved_by_id     :bigint
#
# Indexes
#
#  idx_on_account_id_kanban_board_id_f57807836f                (account_id,kanban_board_id)
#  index_conversation_kanban_states_on_account_id              (account_id)
#  index_conversation_kanban_states_on_board_stage_position    (kanban_board_id,kanban_stage_id,position)
#  index_conversation_kanban_states_on_conversation_and_board  (conversation_id,kanban_board_id) UNIQUE
#  index_conversation_kanban_states_on_conversation_id         (conversation_id)
#  index_conversation_kanban_states_on_kanban_board_id         (kanban_board_id)
#  index_conversation_kanban_states_on_kanban_stage_id         (kanban_stage_id)
#  index_conversation_kanban_states_on_moved_by_id             (moved_by_id)
#
class ConversationKanbanState < ApplicationRecord
  belongs_to :account
  belongs_to :conversation
  belongs_to :kanban_board
  belongs_to :kanban_stage
  belongs_to :moved_by, class_name: 'User', optional: true

  validates :account_id, presence: true
  validates :conversation_id, uniqueness: { scope: :kanban_board_id }
  validates :position, presence: true, numericality: { only_integer: true }
  validate :validate_account_consistency

  scope :ordered, -> { order(position: :asc, id: :asc) }

  private

  def validate_account_consistency
    validate_account_for(:conversation)
    validate_account_for(:kanban_board)
    validate_account_for(:kanban_stage)
    validate_board_for_stage
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
end
