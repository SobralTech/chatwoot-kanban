# == Schema Information
#
# Table name: kanban_board_entry_rules
#
#  id              :bigint           not null, primary key
#  active          :boolean          default(TRUE), not null
#  all_inboxes     :boolean          default(FALSE), not null
#  conditions      :jsonb            not null
#  name            :string           not null
#  position        :integer          default(0), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  kanban_board_id :bigint           not null
#  kanban_stage_id :bigint
#
# Indexes
#
#  index_kanban_board_entry_rules_on_account_id                    (account_id)
#  index_kanban_board_entry_rules_on_kanban_board_id_and_active    (kanban_board_id,active)
#  index_kanban_board_entry_rules_on_kanban_board_id_and_position  (kanban_board_id,position)
#  index_kanban_board_entry_rules_on_kanban_stage_id               (kanban_stage_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (kanban_board_id => kanban_boards.id)
#  fk_rails_...  (kanban_stage_id => kanban_stages.id)
#
# A conversation enters a board when it satisfies one of these rules. The inbox lives in
# `all_inboxes` plus the join table rather than in `conditions`, because the inbox side is
# also the board's manual scope -- the conversation picker and the card filters read it as
# SQL, which a jsonb condition could not serve.
class KanbanBoardEntryRule < ApplicationRecord
  CONDITION_ATTRIBUTES = %w[labels assignee_id team_id priority].freeze

  # Absence is a value rather than an operator, so `assignee_id is_one_of [7, none]` reads
  # as "Ana or nobody" -- a rule that a presence operator could not express in one line.
  NONE_VALUE = 'none'.freeze

  OPERATORS_BY_ATTRIBUTE = {
    'labels' => %w[includes_any includes_all not_includes],
    'assignee_id' => %w[is_one_of is_not_one_of],
    'team_id' => %w[is_one_of is_not_one_of],
    'priority' => %w[is_one_of is_not_one_of]
  }.freeze

  belongs_to :account
  belongs_to :kanban_board
  belongs_to :kanban_stage, optional: true

  has_many :kanban_board_entry_rule_inboxes, dependent: :delete_all
  has_many :inboxes, through: :kanban_board_entry_rule_inboxes

  validates :name, presence: true
  validates :position, presence: true, numericality: { only_integer: true }
  validate :validate_board_account
  validate :validate_stage_consistency
  validate :validate_conditions

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(position: :asc, id: :asc) }

  after_commit :expire_account_activity_cache

  # Asked once per conversation update across the whole account, so the answer is cached
  # and busted whenever a rule is written.
  def self.active_for_account?(account_id)
    Rails.cache.fetch(account_activity_cache_key(account_id), expires_in: 1.hour) do
      active.exists?(account_id: account_id)
    end
  end

  def self.account_activity_cache_key(account_id)
    "kanban_board_entry_rules/active/#{account_id}"
  end

  # Position is the only thing moving and the rules are already valid, so this writes the
  # whole order in one statement instead of revalidating every rule.
  def self.apply_position_order!(ordered_ids)
    return if ordered_ids.empty?

    cases = ordered_ids.each_with_index.map { |id, index| "WHEN #{id.to_i} THEN #{index + 1}" }.join(' ')
    where(id: ordered_ids).update_all( # rubocop:disable Rails/SkipsModelValidations
      ["position = CASE id #{cases} END, updated_at = ?", Time.current]
    )
  end

  def inbox_ids
    kanban_board_entry_rule_inboxes.pluck(:inbox_id)
  end

  private

  def expire_account_activity_cache
    Rails.cache.delete(self.class.account_activity_cache_key(account_id))
  end

  def validate_board_account
    return if kanban_board.blank? || account_id == kanban_board.account_id

    errors.add(:kanban_board, :invalid)
  end

  # A rule that drops cards into the won or lost stage would mark them closed on arrival,
  # so the target is restricted to the stages a card can actually work through.
  def validate_stage_consistency
    return if kanban_stage.blank?

    if kanban_stage.kanban_board_id != kanban_board_id
      errors.add(:kanban_stage, :invalid)
    elsif [kanban_board&.won_stage_id, kanban_board&.lost_stage_id].compact.include?(kanban_stage_id)
      errors.add(:kanban_stage, 'cannot be the won or lost stage')
    end
  end

  def validate_conditions
    Array(conditions).each do |condition|
      condition = condition.with_indifferent_access
      attribute_key = condition[:attribute_key].to_s
      allowed_operators = OPERATORS_BY_ATTRIBUTE[attribute_key]

      next errors.add(:conditions, "unknown attribute #{attribute_key}") if allowed_operators.blank?
      next errors.add(:conditions, "unknown operator for #{attribute_key}") unless allowed_operators.include?(condition[:filter_operator].to_s)

      errors.add(:conditions, "#{attribute_key} needs at least one value") if Array(condition[:values]).compact.blank?
    end
  end
end
