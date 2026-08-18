# == Schema Information
#
# Table name: kanban_card_events
#
#  id              :bigint           not null, primary key
#  event_type      :string           not null
#  metadata        :jsonb            not null
#  created_at      :datetime         not null
#  account_id      :bigint           not null
#  kanban_board_id :bigint           not null
#  kanban_card_id  :bigint           not null
#  user_id         :bigint
#
# Indexes
#
#  idx_on_kanban_board_id_event_type_created_at_095a845e7f    (kanban_board_id,event_type,created_at)
#  index_kanban_card_events_on_account_id                     (account_id)
#  index_kanban_card_events_on_kanban_board_id                (kanban_board_id)
#  index_kanban_card_events_on_kanban_card_id                 (kanban_card_id)
#  index_kanban_card_events_on_kanban_card_id_and_created_at  (kanban_card_id,created_at)
#  index_kanban_card_events_on_user_id                        (user_id)
#
class KanbanCardEvent < ApplicationRecord
  belongs_to :account
  belongs_to :kanban_card, optional: true
  belongs_to :kanban_board
  belongs_to :user, optional: true

  validates :account_id, :kanban_card_id, :kanban_board_id, :event_type, presence: true
  validate :metadata_is_a_hash

  private

  def metadata_is_a_hash
    return if metadata.is_a?(Hash)

    errors.add(:metadata, 'must be a hash')
  end
end
