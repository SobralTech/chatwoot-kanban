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
#  kanban_card_id  :bigint
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
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (kanban_board_id => kanban_boards.id)
#  fk_rails_...  (kanban_card_id => kanban_cards.id) ON DELETE => nullify
#  fk_rails_...  (user_id => users.id) ON DELETE => nullify
#
class KanbanCardEvent < ApplicationRecord
  MOVEMENT_TYPES = %w[stage_changed won lost reopened].freeze

  belongs_to :account
  # Absent only for `card_deleted`, which describes a card row that no longer exists.
  belongs_to :kanban_card, optional: true
  belongs_to :kanban_board
  belongs_to :user, optional: true

  validates :event_type, presence: true

  scope :movements, -> { where(event_type: MOVEMENT_TYPES) }
  scope :recent_first, -> { order(created_at: :desc, id: :desc) }
end
