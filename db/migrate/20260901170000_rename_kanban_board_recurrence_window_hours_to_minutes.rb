class RenameKanbanBoardRecurrenceWindowHoursToMinutes < ActiveRecord::Migration[7.1]
  def up
    rename_column :kanban_boards, :won_recurrence_window_hours, :won_recurrence_window_minutes
    rename_column :kanban_boards, :lost_recurrence_window_hours, :lost_recurrence_window_minutes

    execute 'UPDATE kanban_boards SET won_recurrence_window_minutes = won_recurrence_window_minutes * 60 ' \
            'WHERE won_recurrence_window_minutes IS NOT NULL'
    execute 'UPDATE kanban_boards SET lost_recurrence_window_minutes = lost_recurrence_window_minutes * 60 ' \
            'WHERE lost_recurrence_window_minutes IS NOT NULL'
  end

  def down
    execute 'UPDATE kanban_boards SET won_recurrence_window_minutes = won_recurrence_window_minutes / 60 ' \
            'WHERE won_recurrence_window_minutes IS NOT NULL'
    execute 'UPDATE kanban_boards SET lost_recurrence_window_minutes = lost_recurrence_window_minutes / 60 ' \
            'WHERE lost_recurrence_window_minutes IS NOT NULL'

    rename_column :kanban_boards, :won_recurrence_window_minutes, :won_recurrence_window_hours
    rename_column :kanban_boards, :lost_recurrence_window_minutes, :lost_recurrence_window_hours
  end
end
