class UpdateKanbanConversationCardUniqueIndex < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  BACKFILL_UNIQUE_CONVERSATION_SUBJECTS_SQL = <<~SQL.squish
    WITH normalized_cards AS (
      SELECT
        id,
        NULLIF(LOWER(REGEXP_REPLACE(TRIM(subject), '\\s+', ' ', 'g')), '') AS normalized_subject_value
      FROM kanban_cards
      WHERE origin = 'conversation'
        AND conversation_id IS NOT NULL
        AND subject IS NOT NULL
    ),
    ranked_cards AS (
      SELECT
        id,
        normalized_subject_value,
        ROW_NUMBER() OVER (
          PARTITION BY kanban_board_id, conversation_id, inbox_id, normalized_subject_value
          ORDER BY id
        ) AS duplicate_rank
      FROM kanban_cards
      INNER JOIN normalized_cards USING (id)
      WHERE normalized_subject_value IS NOT NULL
    )
    UPDATE kanban_cards
    SET normalized_subject = ranked_cards.normalized_subject_value
    FROM ranked_cards
    WHERE kanban_cards.id = ranked_cards.id
      AND ranked_cards.duplicate_rank = 1
      AND kanban_cards.normalized_subject IS NULL
  SQL

  def up
    backfill_unique_conversation_subjects

    add_index :kanban_cards,
              [:kanban_board_id, :conversation_id, :inbox_id, :normalized_subject],
              unique: true,
              where: "origin = 'conversation' AND conversation_id IS NOT NULL AND normalized_subject IS NOT NULL",
              name: 'index_kanban_cards_on_conversation_subject_unique',
              algorithm: :concurrently

    remove_index :kanban_cards, name: 'index_kanban_cards_on_board_and_conversation_origin_unique', algorithm: :concurrently
  end

  def down
    add_index :kanban_cards,
              [:kanban_board_id, :conversation_id],
              unique: true,
              where: "origin = 'conversation' AND conversation_id IS NOT NULL",
              name: 'index_kanban_cards_on_board_and_conversation_origin_unique',
              algorithm: :concurrently

    remove_index :kanban_cards, name: 'index_kanban_cards_on_conversation_subject_unique', algorithm: :concurrently
  end

  private

  def backfill_unique_conversation_subjects
    execute BACKFILL_UNIQUE_CONVERSATION_SUBJECTS_SQL
  end
end
