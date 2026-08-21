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
#  lost_recurrence_window_hours        :integer
#  name                                 :string           not null
#  position                             :integer          default(0), not null
#  use_opportunity_card_reads           :boolean          default(TRUE), not null
#  visibility_mode                      :string           default("all_agents"), not null
#  created_at                           :datetime         not null
#  updated_at                           :datetime         not null
#  account_id                           :bigint           not null
#  lost_stage_id                        :bigint
#  won_recurrence_enabled               :boolean          default(FALSE), not null
#  won_recurrence_window_hours         :integer
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
  has_many :allowed_inboxes, through: :kanban_board_inboxes, source: :inbox
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
  scope :accepting_inbox, lambda { |inbox_id|
    joins_sql = KanbanBoardInbox.where('kanban_board_inboxes.kanban_board_id = kanban_boards.id')
                                .where(inbox_id: inbox_id)
                                .select('1').to_sql
    where("inbox_scope_mode = 'all_inboxes' OR (inbox_scope_mode = 'selected_inboxes' AND EXISTS (#{joins_sql}))")
  }
  scope :accepting_inbox_for_account, lambda { |account_id, inbox_id|
    active.where(account_id: account_id).accepting_inbox(inbox_id)
  }

  def assignable_users
    all_agents? ? account.users : visible_users
  end

  def inbox_allowed?(inbox_or_id)
    inbox_id = inbox_or_id.is_a?(Inbox) ? inbox_or_id.id : inbox_or_id.to_i

    return false if inbox_id.blank?

    if all_inboxes?
      Inbox.exists?(account_id: account_id, id: inbox_id)
    else
      kanban_board_inboxes.exists?(inbox_id: inbox_id)
    end
  end

  def recurrence_window_hours_for(stage_id)
    return won_recurrence_window_hours if stage_id == won_stage_id && won_recurrence_enabled?
    return lost_recurrence_window_hours if stage_id == lost_stage_id && lost_recurrence_enabled?
  end

  private

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
      window_attribute = "#{stage_type}_recurrence_window_hours"

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
