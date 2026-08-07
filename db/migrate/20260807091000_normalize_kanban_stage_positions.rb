class NormalizeKanbanStagePositions < ActiveRecord::Migration[7.1]
  def up
    select_all('SELECT id, won_stage_id, lost_stage_id FROM kanban_boards').each do |board|
      next if board['won_stage_id'].blank? && board['lost_stage_id'].blank?

      if board['won_stage_id'].present? && board['won_stage_id'] == board['lost_stage_id']
        Rails.logger.warn("Kanban board #{board['id']} has the same won and lost stage; clearing lost_stage_id")
        connection.execute("UPDATE kanban_boards SET lost_stage_id = NULL, updated_at = #{quoted_now} WHERE id = #{quote(board['id'])}")
        board['lost_stage_id'] = nil
      end

      normalize_positions(board)
    end
  end

  def down; end

  private

  def normalize_positions(board)
    stages = select_all(<<~SQL.squish)
      SELECT id, position FROM kanban_stages
      WHERE kanban_board_id = #{quote(board['id'])} AND active = TRUE
      ORDER BY position ASC, created_at ASC, id ASC
    SQL
    special_stage_ids = [board['won_stage_id'], board['lost_stage_id']].compact.uniq
    regular_stages, special_stages = stages.partition { |stage| special_stage_ids.exclude?(stage['id']) }

    (regular_stages + special_stages).each.with_index(1) do |stage, position|
      next if stage['position'].to_i == position

      connection.execute("UPDATE kanban_stages SET position = #{quote(position)}, updated_at = #{quoted_now} WHERE id = #{quote(stage['id'])}")
    end
  end

  def select_all(sql)
    connection.select_all(sql).to_a
  end

  def quote(value)
    connection.quote(value)
  end

  def quoted_now
    quote(Time.current)
  end
end
