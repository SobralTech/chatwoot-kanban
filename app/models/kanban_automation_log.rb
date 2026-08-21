# == Schema Information
#
# Table name: kanban_automation_logs
#
#  id                        :bigint           not null, primary key
#  details                   :jsonb            not null
#  event_name                :string           not null
#  status                    :string           not null
#  created_at                :datetime         not null
#  account_id                :bigint           not null
#  kanban_automation_rule_id :bigint           not null
#  kanban_card_id            :bigint
#
# Indexes
#
#  index_kanban_automation_logs_on_account_id                 (account_id)
#  index_kanban_automation_logs_on_card_and_created_at        (kanban_card_id,created_at)
#  index_kanban_automation_logs_on_kanban_automation_rule_id  (kanban_automation_rule_id)
#  index_kanban_automation_logs_on_rule_and_created_at        (kanban_automation_rule_id,created_at)
#
# Foreign Keys
#
#  fk_rails_...  (kanban_automation_rule_id => kanban_automation_rules.id) ON DELETE => cascade
#  fk_rails_...  (kanban_card_id => kanban_cards.id) ON DELETE => nullify
#
class KanbanAutomationLog < ApplicationRecord
  STATUSES = %w[matched skipped executed simulated failed].freeze

  belongs_to :account
  belongs_to :kanban_automation_rule
  belongs_to :kanban_card, optional: true

  validates :event_name, :status, presence: true
  validates :status, inclusion: { in: STATUSES }
end
