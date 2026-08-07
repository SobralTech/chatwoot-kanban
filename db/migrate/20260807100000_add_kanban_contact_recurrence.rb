class AddKanbanContactRecurrence < ActiveRecord::Migration[7.1]
  def change
    add_column :kanban_boards, :won_recurrence_enabled, :boolean, null: false, default: false
    add_column :kanban_boards, :won_recurrence_window_hours, :integer
    add_column :kanban_boards, :lost_recurrence_enabled, :boolean, null: false, default: false
    add_column :kanban_boards, :lost_recurrence_window_hours, :integer

    add_reference :kanban_cards, :recreated_from_card,
                  foreign_key: { to_table: :kanban_cards, on_delete: :nullify },
                  index: true
  end
end
