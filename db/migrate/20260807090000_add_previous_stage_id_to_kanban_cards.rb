class AddPreviousStageIdToKanbanCards < ActiveRecord::Migration[7.1]
  def change
    add_reference :kanban_cards, :previous_stage,
                  foreign_key: { to_table: :kanban_stages, on_delete: :nullify },
                  index: true
  end
end
