class AddAutomationSettingsToKanbanBoards < ActiveRecord::Migration[7.1]
  def change
    add_column :kanban_boards, :automation_settings, :jsonb, null: false, default: {}
  end
end
