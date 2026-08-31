# The create/preview flow already gates a rule behind a "this affects N conversations"
# confirmation before it can save, so a new rule no longer needs a second manual step to
# start acting on conversations.
class ChangeKanbanBoardEntryRulesActiveDefault < ActiveRecord::Migration[7.1]
  def change
    change_column_default :kanban_board_entry_rules, :active, from: false, to: true
  end
end
