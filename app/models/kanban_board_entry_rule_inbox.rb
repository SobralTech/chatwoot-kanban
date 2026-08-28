# == Schema Information
#
# Table name: kanban_board_entry_rule_inboxes
#
#  id                         :bigint           not null, primary key
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  account_id                 :bigint           not null
#  inbox_id                   :bigint           not null
#  kanban_board_entry_rule_id :bigint           not null
#  kanban_board_id            :bigint           not null
#
# Indexes
#
#  index_entry_rule_inboxes_on_board_and_inbox          (kanban_board_id,inbox_id)
#  index_entry_rule_inboxes_on_rule_and_inbox           (kanban_board_entry_rule_id,inbox_id) UNIQUE
#  index_kanban_board_entry_rule_inboxes_on_account_id  (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (inbox_id => inboxes.id)
#  fk_rails_...  (kanban_board_entry_rule_id => kanban_board_entry_rules.id)
#  fk_rails_...  (kanban_board_id => kanban_boards.id)
#
# `kanban_board_id` is denormalised from the rule so the board's inbox scope is a single
# index lookup: the conversation picker asks it on every render.
class KanbanBoardEntryRuleInbox < ApplicationRecord
  belongs_to :account
  belongs_to :kanban_board
  belongs_to :kanban_board_entry_rule
  belongs_to :inbox

  validates :inbox_id, uniqueness: { scope: :kanban_board_entry_rule_id }
end
