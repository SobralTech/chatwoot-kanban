class AddUseOpportunityCardReadsToKanbanBoards < ActiveRecord::Migration[7.1]
  def change
    add_column :kanban_boards, :use_opportunity_card_reads, :boolean, null: false, default: false
  end
end
