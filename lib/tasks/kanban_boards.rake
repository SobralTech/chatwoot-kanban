# frozen_string_literal: true

namespace :kanban_boards do
  desc 'Backfill default_stage_id for existing kanban_boards'
  task backfill_default_stages: :environment do
    KanbanBoardsDefaultStagesBackfill.new.run
  end
end

class KanbanBoardsDefaultStagesBackfill
  def initialize
    @batch_size = ENV.fetch('BATCH_SIZE', 1000).to_i
    @dry_run = ENV.fetch('DRY_RUN', 'false').casecmp('true').zero?
    @summary = initial_summary
  end

  def run
    abort 'BATCH_SIZE must be greater than 0' unless batch_size.positive?

    puts "Starting kanban_boards default stages backfill. batch_size=#{batch_size}, dry_run=#{dry_run}"
    process_batches
    print_summary
  end

  private

  attr_reader :batch_size, :dry_run, :summary

  def initial_summary
    {
      scanned_boards: 0,
      eligible_boards: 0,
      updated_boards: 0,
      already_configured_boards: 0,
      skipped_inactive_boards: 0,
      skipped_without_active_stage: 0
    }
  end

  def process_batches
    last_id = 0

    loop do
      ids = next_batch_ids(last_id)
      break if ids.empty?

      process_batch(ids)
      last_id = ids.last
    end
  end

  def next_batch_ids(last_id)
    connection.select_values(
      sanitize_sql([
                     'SELECT id FROM kanban_boards WHERE id > ? ORDER BY id ASC LIMIT ?',
                     last_id,
                     batch_size
                   ])
    )
  end

  def process_batch(ids)
    batch_stats = batch_counts(ids)
    merge_batch_counts(batch_stats)

    summary[:updated_boards] += update_batch(ids) unless dry_run
  end

  def batch_counts(ids)
    row = connection.exec_query(batch_counts_sql(ids)).first

    {
      scanned_boards: row['scanned_boards'].to_i,
      eligible_boards: row['eligible_boards'].to_i,
      already_configured_boards: row['already_configured_boards'].to_i,
      skipped_inactive_boards: row['skipped_inactive_boards'].to_i,
      skipped_without_active_stage: row['skipped_without_active_stage'].to_i
    }
  end

  def merge_batch_counts(batch_stats)
    batch_stats.each do |key, count|
      summary[key] += count
    end
  end

  def update_batch(ids)
    connection.exec_query(update_sql(ids)).rows.size
  end

  def batch_counts_sql(ids)
    <<~SQL.squish
      SELECT
        COUNT(*) AS scanned_boards,
        COUNT(*) FILTER (WHERE kb.active = TRUE AND kb.default_stage_id IS NULL) AS eligible_boards,
        COUNT(*) FILTER (WHERE kb.active = TRUE AND kb.default_stage_id IS NOT NULL) AS already_configured_boards,
        COUNT(*) FILTER (WHERE kb.active = FALSE) AS skipped_inactive_boards,
        COUNT(*) FILTER (
          WHERE kb.active = TRUE AND kb.default_stage_id IS NULL AND first_stage.id IS NULL
        ) AS skipped_without_active_stage
      FROM kanban_boards kb
      LEFT JOIN LATERAL (
        #{first_active_stage_sql}
      ) first_stage ON TRUE
      WHERE kb.id IN (#{quoted_ids(ids)})
    SQL
  end

  def update_sql(ids)
    <<~SQL.squish
      WITH selected_defaults AS (
        SELECT kb.id AS board_id, first_stage.id AS default_stage_id
        FROM kanban_boards kb
        INNER JOIN LATERAL (
          #{first_active_stage_sql}
        ) first_stage ON TRUE
        WHERE kb.id IN (#{quoted_ids(ids)})
          AND kb.active = TRUE
          AND kb.default_stage_id IS NULL
      )
      UPDATE kanban_boards kb
      SET default_stage_id = selected_defaults.default_stage_id,
          updated_at = CURRENT_TIMESTAMP
      FROM selected_defaults
      WHERE kb.id = selected_defaults.board_id
      RETURNING kb.id
    SQL
  end

  def first_active_stage_sql
    <<~SQL.squish
      SELECT ks.id
      FROM kanban_stages ks
      WHERE ks.kanban_board_id = kb.id
        AND ks.active = TRUE
      ORDER BY ks.position ASC, ks.created_at ASC, ks.id ASC
      LIMIT 1
    SQL
  end

  def quoted_ids(ids)
    ids.map { |id| connection.quote(id) }.join(',')
  end

  def print_summary
    puts 'Kanban boards default stages backfill summary:'
    puts "scanned_boards: #{summary[:scanned_boards]}"
    puts "eligible_boards: #{summary[:eligible_boards]}"
    puts "updated_boards: #{summary[:updated_boards]}"
    puts "already_configured_boards: #{summary[:already_configured_boards]}"
    puts "skipped_inactive_boards: #{summary[:skipped_inactive_boards]}"
    puts "skipped_without_active_stage: #{summary[:skipped_without_active_stage]}"
    puts "batch_size: #{batch_size}"
    puts "dry_run: #{dry_run}"
  end

  def connection
    ActiveRecord::Base.connection
  end

  def sanitize_sql(array)
    ActiveRecord::Base.sanitize_sql_array(array)
  end
end
