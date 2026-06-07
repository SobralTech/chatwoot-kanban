# == Schema Information
#
# Table name: kanban_boards
#
#  id                                   :bigint           not null, primary key
#  active                               :boolean          default(TRUE), not null
#  auto_create_cards_from_conversations :boolean          default(FALSE), not null
#  description                          :text
#  inbox_scope_mode                     :string           default("all_inboxes"), not null
#  name                                 :string           not null
#  position                             :integer          default(0), not null
#  use_opportunity_card_reads           :boolean          default(TRUE), not null
#  visibility_mode                      :string           default("all_agents"), not null
#  created_at                           :datetime         not null
#  updated_at                           :datetime         not null
#  account_id                           :bigint           not null
#
# Indexes
#
#  index_active_kanban_boards_on_account_id_and_name  (account_id,name) UNIQUE WHERE (active = true)
#  index_kanban_boards_on_account_id                  (account_id)
#  index_kanban_boards_on_account_id_and_active       (account_id,active)
#  index_kanban_boards_on_account_id_and_position     (account_id,position)
#
class KanbanBoard < ApplicationRecord
  INBOX_SCOPE_MODES = %w[all_inboxes selected_inboxes].freeze
  VISIBILITY_MODES = %w[all_agents selected_agents].freeze

  belongs_to :account

  has_many :kanban_stages, dependent: :destroy_async
  has_many :conversation_kanban_states, dependent: :destroy_async
  has_many :kanban_cards, dependent: nil
  has_many :kanban_board_members, dependent: :destroy_async
  has_many :visible_users, through: :kanban_board_members, source: :user
  has_many :kanban_board_inboxes, dependent: :destroy_async
  has_many :allowed_inboxes, through: :kanban_board_inboxes, source: :inbox

  attribute :visibility_mode, :string, default: 'all_agents'
  enum :visibility_mode, VISIBILITY_MODES.index_by(&:itself), validate: true

  attribute :inbox_scope_mode, :string, default: 'all_inboxes'
  enum :inbox_scope_mode, INBOX_SCOPE_MODES.index_by(&:itself), validate: true

  validates :account_id, presence: true
  validates :name, presence: true, uniqueness: { scope: :account_id, conditions: -> { active } }, if: :active?
  validates :position, presence: true, numericality: { only_integer: true }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(position: :asc, id: :asc) }
  scope :accepting_inbox, lambda { |inbox_id|
    joins_sql = KanbanBoardInbox.where('kanban_board_inboxes.kanban_board_id = kanban_boards.id')
                                .where(inbox_id: inbox_id)
                                .select('1').to_sql
    where("inbox_scope_mode = 'all_inboxes' OR (inbox_scope_mode = 'selected_inboxes' AND EXISTS (#{joins_sql}))")
  }

  def inbox_allowed?(inbox_or_id)
    inbox_id = inbox_or_id.is_a?(Inbox) ? inbox_or_id.id : inbox_or_id.to_i

    return false if inbox_id.blank?

    if all_inboxes?
      Inbox.exists?(account_id: account_id, id: inbox_id)
    else
      kanban_board_inboxes.exists?(inbox_id: inbox_id)
    end
  end
end
