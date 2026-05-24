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

  scope :ordered, -> { order(position: :asc, created_at: :asc, id: :asc) }

  def self.normalize_positions_for_stage!(kanban_board:, kanban_stage:)
    transaction do
      where(kanban_board: kanban_board, kanban_stage: kanban_stage).ordered.each.with_index(1) do |state, position|
        state.update!(position: position) if state.position != position
      end
    end
  end

  def reorder_to_position!(target_stage:, target_position:, moved_by:, moved_at:)
    previous_stage = kanban_stage

    normalize_reorder_stages!(previous_stage, target_stage)
    reload

    reordered_states = reordered_stage_states(target_stage, target_position)
    update_stage_positions!(reordered_states, target_stage, moved_by: moved_by, moved_at: moved_at)
    normalize_previous_stage!(previous_stage, target_stage)
    reload
  end

  private

  def normalize_reorder_stages!(previous_stage, target_stage)
    self.class.normalize_positions_for_stage!(kanban_board: kanban_board, kanban_stage: previous_stage)
    return if previous_stage == target_stage

    self.class.normalize_positions_for_stage!(kanban_board: kanban_board, kanban_stage: target_stage)
  end

  def reordered_stage_states(target_stage, target_position)
    states = stage_states_without_self(target_stage)
    clamped_position = target_position.to_i.clamp(1, states.length + 1)

    states.insert(clamped_position - 1, self)
  end

  def stage_states_without_self(stage)
    self.class.where(kanban_board: kanban_board, kanban_stage: stage).where.not(id: id).ordered.to_a
  end

  def update_stage_positions!(states, target_stage, moved_by:, moved_at:)
    states.each_with_index do |state, index|
      attributes = changed_position_attributes_for(state, target_stage, index + 1, moved_by, moved_at)
      state.update!(attributes) if attributes.present?
    end
  end

  def changed_position_attributes_for(state, target_stage, position, moved_by, moved_at)
    attributes = {}
    attributes[:position] = position if state.position != position
    return attributes if state != self

    attributes[:kanban_stage] = target_stage if state.kanban_stage != target_stage
    attributes[:moved_by] = moved_by
    attributes[:moved_at] = moved_at
    attributes
  end

  def normalize_previous_stage!(previous_stage, target_stage)
    return if previous_stage == target_stage

    self.class.normalize_positions_for_stage!(kanban_board: kanban_board, kanban_stage: previous_stage)
  end

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
