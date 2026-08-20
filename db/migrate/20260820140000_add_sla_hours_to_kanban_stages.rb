class AddSlaHoursToKanbanStages < ActiveRecord::Migration[7.1]
  def change
    add_column :kanban_stages, :sla_hours, :integer
  end
end
