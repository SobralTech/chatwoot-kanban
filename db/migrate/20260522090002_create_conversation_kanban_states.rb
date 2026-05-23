class CreateConversationKanbanStates < ActiveRecord::Migration[7.1]
  def change
    create_table :conversation_kanban_states do |t|
      t.references :account, null: false, index: true
      t.references :conversation, null: false, index: true
      t.references :kanban_board, null: false, index: true
      t.references :kanban_stage, null: false, index: true
      t.integer :position, null: false, default: 0
      t.bigint :moved_by_id
      t.datetime :moved_at

      t.timestamps
    end

    add_index :conversation_kanban_states, [:conversation_id, :kanban_board_id],
              unique: true, name: 'index_conversation_kanban_states_on_conversation_and_board'
    add_index :conversation_kanban_states, [:kanban_board_id, :kanban_stage_id, :position],
              name: 'index_conversation_kanban_states_on_board_stage_position'
    add_index :conversation_kanban_states, [:account_id, :kanban_board_id]
    add_index :conversation_kanban_states, :moved_by_id
  end
end
