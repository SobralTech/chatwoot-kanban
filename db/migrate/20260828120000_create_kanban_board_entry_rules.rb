class CreateKanbanBoardEntryRules < ActiveRecord::Migration[7.1]
  def up
    create_rules_table!
    create_rule_inboxes_table!
    backfill_entry_rules!
  end

  def down
    drop_table :kanban_board_entry_rule_inboxes
    drop_table :kanban_board_entry_rules
  end

  private

  def create_rules_table!
    create_table :kanban_board_entry_rules do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.references :kanban_board, null: false, foreign_key: true, index: false
      t.references :kanban_stage, null: true, foreign_key: true, index: false
      t.string :name, null: false
      t.boolean :active, null: false, default: false
      t.boolean :all_inboxes, null: false, default: false
      t.integer :position, null: false, default: 0
      t.jsonb :conditions, null: false, default: []
      t.timestamps
    end

    add_index :kanban_board_entry_rules, [:kanban_board_id, :position]
    add_index :kanban_board_entry_rules, [:kanban_board_id, :active]
    add_index :kanban_board_entry_rules, :account_id
    add_index :kanban_board_entry_rules, :kanban_stage_id
  end

  def create_rule_inboxes_table!
    create_table :kanban_board_entry_rule_inboxes do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.references :kanban_board, null: false, foreign_key: true, index: false
      t.references :kanban_board_entry_rule, null: false, foreign_key: true, index: false
      t.references :inbox, null: false, foreign_key: true, index: false
      t.timestamps
    end

    # The board-scoped lookup is the hot one: every conversation picker and card filter
    # asks "does this board accept inbox X?", which reads this index alone.
    add_index :kanban_board_entry_rule_inboxes, [:kanban_board_id, :inbox_id],
              name: 'index_entry_rule_inboxes_on_board_and_inbox'
    add_index :kanban_board_entry_rule_inboxes, [:kanban_board_entry_rule_id, :inbox_id],
              unique: true, name: 'index_entry_rule_inboxes_on_rule_and_inbox'
    add_index :kanban_board_entry_rule_inboxes, :account_id
  end

  # Boards that auto-created cards become an active rule; boards that only narrowed their
  # inbox scope become an inactive one, so the configuration survives even though an
  # inactive rule no longer narrows anything.
  def backfill_entry_rules!
    execute(<<~SQL.squish)
      INSERT INTO kanban_board_entry_rules
        (account_id, kanban_board_id, name, active, all_inboxes, position, conditions, created_at, updated_at)
      SELECT account_id, id, 'Conversas novas', auto_create_cards_from_conversations,
             inbox_scope_mode = 'all_inboxes', 1, '[]'::jsonb, NOW(), NOW()
      FROM kanban_boards
      WHERE auto_create_cards_from_conversations = TRUE OR inbox_scope_mode = 'selected_inboxes'
    SQL

    execute(<<~SQL.squish)
      INSERT INTO kanban_board_entry_rule_inboxes
        (account_id, kanban_board_id, kanban_board_entry_rule_id, inbox_id, created_at, updated_at)
      SELECT bi.account_id, bi.kanban_board_id, r.id, bi.inbox_id, NOW(), NOW()
      FROM kanban_board_inboxes bi
      INNER JOIN kanban_board_entry_rules r ON r.kanban_board_id = bi.kanban_board_id
      WHERE r.all_inboxes = FALSE
    SQL
  end
end
