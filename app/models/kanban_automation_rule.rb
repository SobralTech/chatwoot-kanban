# == Schema Information
#
# Table name: kanban_automation_rules
#
#  id               :bigint           not null, primary key
#  actions          :jsonb            not null
#  active           :boolean          default(FALSE), not null
#  conditions       :jsonb            not null
#  description      :text
#  dry_run          :boolean          default(TRUE), not null
#  event_name       :string           not null
#  name             :string           not null
#  position         :integer          default(0), not null
#  stop_after_match :boolean          default(FALSE), not null
#  threshold_hours  :integer
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint           not null
#  created_by_id    :bigint
#  kanban_board_id  :bigint           not null
#
# Indexes
#
#  index_kanban_automation_rules_on_account_id          (account_id)
#  index_kanban_automation_rules_on_board_event_active  (kanban_board_id,event_name,active)
#  index_kanban_automation_rules_on_created_by_id       (created_by_id)
#  index_kanban_automation_rules_on_kanban_board_id     (kanban_board_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (kanban_board_id => kanban_boards.id)
#
class KanbanAutomationRule < ApplicationRecord
  EVENTS = %w[
    card_created stage_changed card_won card_lost card_reopened
    card_stalled due_soon overdue no_reply
  ].freeze

  TIME_BASED_EVENTS = %w[card_stalled due_soon overdue no_reply].freeze

  # `overdue` needs no threshold: a card is either past due_at or it is not.
  THRESHOLD_EVENTS = %w[card_stalled due_soon no_reply].freeze

  CONDITION_ATTRIBUTES = %w[
    stage_id previous_stage_id priority labels assignee_id inbox_id
    total_value hours_in_stage reason_id origin contact_has_open_card
  ].freeze

  FILTER_OPERATORS = %w[
    equal_to not_equal_to is_present is_not_present greater_than
    less_than is_one_of includes
  ].freeze

  ACTION_NAMES = %w[
    move_to_stage assign_agents set_priority add_label remove_label
    set_due_at create_note send_message send_private_note notify_agents
    mark_as_lost create_card_in_board send_webhook
  ].freeze

  belongs_to :account
  belongs_to :kanban_board
  belongs_to :created_by, class_name: 'User', optional: true

  has_many :kanban_automation_logs, dependent: :delete_all

  validates :account_id, :kanban_board_id, :name, :event_name, :position, presence: true
  validates :position, numericality: { only_integer: true }
  validates :threshold_hours, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :threshold_hours, presence: true, if: :threshold_required?

  validate :validate_board_account
  validate :validate_created_by_account
  validate :validate_rule_definition

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(position: :asc, id: :asc) }

  def threshold_required?
    THRESHOLD_EVENTS.include?(event_name.to_s)
  end

  private

  def validate_rule_definition
    KanbanAutomations::RuleValidator.new(self).validate
  end

  def validate_board_account
    return if kanban_board.blank? || account_id == kanban_board.account_id

    errors.add(:kanban_board, :invalid)
  end

  def validate_created_by_account
    return if created_by.blank? || account.blank?
    return if AccountUser.exists?(account_id: account_id, user_id: created_by_id)

    errors.add(:created_by, :invalid)
  end
end
