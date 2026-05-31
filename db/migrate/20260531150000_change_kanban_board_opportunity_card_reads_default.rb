class ChangeKanbanBoardOpportunityCardReadsDefault < ActiveRecord::Migration[7.1]
  def change
    change_column_default :kanban_boards, :use_opportunity_card_reads, from: false, to: true
  end
end
