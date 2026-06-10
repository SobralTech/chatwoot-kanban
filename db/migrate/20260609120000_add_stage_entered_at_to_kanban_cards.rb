class AddStageEnteredAtToKanbanCards < ActiveRecord::Migration[7.1]
  def up
    add_column :kanban_cards, :stage_entered_at, :datetime

    kanban_card_model.reset_column_information
    kanban_card_model.unscoped.where(stage_entered_at: nil).update_all('stage_entered_at = created_at') # rubocop:disable Rails/SkipsModelValidations

    change_column_null :kanban_cards, :stage_entered_at, false
  end

  def down
    remove_column :kanban_cards, :stage_entered_at
  end

  private

  def kanban_card_model
    @kanban_card_model ||= Class.new(ActiveRecord::Base) do
      self.table_name = 'kanban_cards'
    end
  end
end
