# == Schema Information
#
# Table name: kanban_boards
#
#  id                                   :bigint           not null, primary key
#  active                               :boolean          default(TRUE), not null
#  auto_create_cards_from_conversations :boolean          default(FALSE), not null
#  automation_settings                  :jsonb            not null
#  description                          :text
#  inbox_scope_mode                     :string           default("all_inboxes"), not null
#  lost_reason_required                 :boolean          default(FALSE), not null
#  lost_recurrence_enabled              :boolean          default(FALSE), not null
#  lost_recurrence_window_minutes       :integer
#  name                                 :string           not null
#  position                             :integer          default(0), not null
#  use_opportunity_card_reads           :boolean          default(TRUE), not null
#  visibility_mode                      :string           default("all_agents"), not null
#  won_recurrence_enabled               :boolean          default(FALSE), not null
#  won_recurrence_window_minutes        :integer
#  created_at                           :datetime         not null
#  updated_at                           :datetime         not null
#  account_id                           :bigint           not null
#  lost_stage_id                        :bigint
#  won_stage_id                         :bigint
#
# Indexes
#
#  index_active_kanban_boards_on_account_id_and_name  (account_id,name) UNIQUE WHERE (active = true)
#  index_kanban_boards_on_account_id                  (account_id)
#  index_kanban_boards_on_account_id_and_active       (account_id,active)
#  index_kanban_boards_on_account_id_and_position     (account_id,position)
#  index_kanban_boards_on_lost_stage_id               (lost_stage_id)
#  index_kanban_boards_on_won_stage_id                (won_stage_id)
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
  has_many :kanban_board_entry_rules, dependent: :destroy_async
  has_many :kanban_board_entry_rule_inboxes, dependent: :delete_all
  has_many :kanban_custom_fields, dependent: :destroy_async
  has_many :kanban_reasons, dependent: :destroy_async
  has_many :kanban_automation_rules, dependent: :destroy_async
  has_many :kanban_automation_logs, through: :kanban_automation_rules

  belongs_to :won_stage, class_name: 'KanbanStage', optional: true, inverse_of: false
  belongs_to :lost_stage, class_name: 'KanbanStage', optional: true, inverse_of: false

  attribute :visibility_mode, :string, default: 'all_agents'
  enum :visibility_mode, VISIBILITY_MODES.index_by(&:itself), validate: true

  attribute :inbox_scope_mode, :string, default: 'all_inboxes'
  enum :inbox_scope_mode, INBOX_SCOPE_MODES.index_by(&:itself), validate: true

  validates :account_id, presence: true
  validates :name, presence: true, uniqueness: { scope: :account_id, conditions: -> { active } }, if: :active?
  validates :position, presence: true, numericality: { only_integer: true }
  validate :validate_won_stage_consistency
  validate :validate_lost_stage_consistency
  validate :validate_won_lost_stages_are_different
  validate :validate_won_lost_stage_required_on_activation
  validate :validate_recurrence_windows

  after_update :reposition_special_stages, if: :special_stage_assignment_changed?

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(position: :asc, id: :asc) }
  # A board's inbox scope is the union of the inboxes its active entry rules name. No
  # active rule means nothing is narrowing the board, which reads as open rather than
  # closed: a board still being set up has to stay usable by hand.
  scope :accepting_inbox, lambda { |inbox_id|
    active_rules = KanbanBoardEntryRule.active.where('kanban_board_entry_rules.kanban_board_id = kanban_boards.id')
    named_inbox = KanbanBoardEntryRuleInbox
                  .where('kanban_board_entry_rule_inboxes.kanban_board_id = kanban_boards.id')
                  .where(inbox_id: inbox_id)
                  .where(kanban_board_entry_rule_id: KanbanBoardEntryRule.active.select(:id))

    where(
      "NOT EXISTS (#{active_rules.select('1').to_sql}) " \
      "OR EXISTS (#{active_rules.where(all_inboxes: true).select('1').to_sql}) " \
      "OR EXISTS (#{named_inbox.select('1').to_sql})"
    )
  }
  scope :accepting_inbox_for_account, lambda { |account_id, inbox_id|
    active.where(account_id: account_id).accepting_inbox(inbox_id)
  }

  # The avatar is rendered for every assignable user, so the attachment is preloaded here
  # rather than in each view: without it a board with a large team costs one query per user.
  def assignable_users
    (all_agents? ? account.users : visible_users).includes(avatar_attachment: :blob)
  end

  def inbox_allowed?(inbox_or_id)
    inbox_id = inbox_or_id.is_a?(Inbox) ? inbox_or_id.id : inbox_or_id.to_i

    return false if inbox_id.blank?
    return false unless Inbox.exists?(account_id: account_id, id: inbox_id)

    return true if derived_all_inboxes?

    kanban_board_entry_rule_inboxes.where(kanban_board_entry_rule_id: active_entry_rule_ids).exists?(inbox_id: inbox_id)
  end

  # The payload keeps the `inbox_scope_mode` / `allowed_inboxes` shape the dashboard has
  # always read; only where the answer comes from has changed.
  def derived_inbox_scope_mode
    derived_all_inboxes? ? 'all_inboxes' : 'selected_inboxes'
  end

  def derived_allowed_inbox_ids
    return [] if derived_all_inboxes?

    kanban_board_entry_rule_inboxes.where(kanban_board_entry_rule_id: active_entry_rule_ids).distinct.pluck(:inbox_id).sort
  end

  def derived_all_inboxes?
    active_rules = kanban_board_entry_rules.active
    !active_rules.exists? || active_rules.exists?(all_inboxes: true)
  end

  def recurrence_window_minutes_for(stage_id)
    return won_recurrence_window_minutes if stage_id == won_stage_id && won_recurrence_enabled?
    return lost_recurrence_window_minutes if stage_id == lost_stage_id && lost_recurrence_enabled?
  end

  private

  def active_entry_rule_ids
    kanban_board_entry_rules.active.select(:id)
  end

  def validate_won_stage_consistency
    return if won_stage.blank?
    return if won_stage.kanban_board_id == id && won_stage.account_id == account_id

    errors.add(:won_stage, :invalid)
  end

  def validate_lost_stage_consistency
    return if lost_stage.blank?
    return if lost_stage.kanban_board_id == id && lost_stage.account_id == account_id

    errors.add(:lost_stage, :invalid)
  end

  def validate_won_lost_stages_are_different
    return if won_stage_id.blank? || lost_stage_id.blank? || won_stage_id != lost_stage_id

    errors.add(:lost_stage, 'must be different from the won stage')
  end

  def validate_won_lost_stage_required_on_activation
    return unless will_save_change_to_active? && active?
    return if won_stage_id.blank? || lost_stage_id.blank?
    return if kanban_stages.active.where.not(id: [won_stage_id, lost_stage_id]).exists?

    errors.add(:base, 'Won stage, lost stage, and an active regular stage must be set before activating this board')
  end

  def validate_recurrence_windows
    %i[won lost].each do |stage_type|
      enabled = public_send("#{stage_type}_recurrence_enabled")
      window_attribute = "#{stage_type}_recurrence_window_minutes"

      errors.add(window_attribute, :blank) if enabled && public_send(window_attribute).blank?
    end
  end

  def special_stage_assignment_changed?
    saved_change_to_won_stage_id? || saved_change_to_lost_stage_id?
  end

  def reposition_special_stages
    newly_assigned_stage_ids = %i[won_stage_id lost_stage_id].filter_map do |attribute|
      previous_id, current_id = saved_change_to_attribute(attribute)
      current_id if previous_id != current_id && current_id.present?
    end

    KanbanStage.reposition_special_stages_for_board!(self, newly_assigned_stage_ids: newly_assigned_stage_ids)
  end
end
