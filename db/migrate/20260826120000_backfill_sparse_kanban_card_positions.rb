class BackfillSparseKanbanCardPositions < ActiveRecord::Migration[7.1]
  # Positions used to be dense (1..N), so dropping a card anywhere but the end meant
  # renumbering the whole stage. Spacing active cards KanbanCard::POSITION_GAP apart leaves
  # room to place a card between two neighbours by writing a single row.
  def up
    respace_active_cards('* 1000')
  end

  def down
    respace_active_cards('')
  end

  private

  def respace_active_cards(spacing)
    execute(<<~SQL.squish)
      WITH ordered_cards AS (
        SELECT id,
               row_number() OVER (
                 PARTITION BY kanban_board_id, kanban_stage_id
                 ORDER BY position ASC, created_at ASC, id ASC
               ) #{spacing} AS respaced_position
        FROM kanban_cards
        WHERE active = TRUE
      )
      UPDATE kanban_cards
      SET position = ordered_cards.respaced_position
      FROM ordered_cards
      WHERE kanban_cards.id = ordered_cards.id
        AND kanban_cards.position != ordered_cards.respaced_position
    SQL
  end
end
