# frozen_string_literal: true

namespace :kanban_cards do
  desc 'Backfill kanban_cards from conversation_kanban_states'
  task backfill: :environment do
    KanbanCardsBackfill.new.run
  end
end

class KanbanCardsBackfill
  SKIP_REASONS = %w[
    missing_conversation
    missing_contact
    missing_inbox
    missing_board
    missing_stage
    account_mismatch
    stage_board_mismatch
  ].freeze

  def initialize
    @batch_size = ENV.fetch('BATCH_SIZE', 1000).to_i
    @dry_run = ENV.fetch('DRY_RUN', 'false').casecmp('true').zero?
    @summary = initial_summary
  end

  def run
    abort 'BATCH_SIZE must be greater than 0' unless batch_size.positive?

    puts "Starting kanban_cards backfill. batch_size=#{batch_size}, dry_run=#{dry_run}"
    process_batches
    print_summary
  end

  private

  attr_reader :batch_size, :dry_run, :summary

  def initial_summary
    {
      scanned: 0,
      eligible: 0,
      inserted: 0,
      conflicted: 0,
      skipped: 0,
      skipped_by_reason: SKIP_REASONS.index_with(0)
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
                     'SELECT id FROM conversation_kanban_states WHERE id > ? ORDER BY id ASC LIMIT ?',
                     last_id,
                     batch_size
                   ])
    )
  end

  def process_batch(ids)
    batch_stats = batch_counts(ids)
    merge_batch_counts(batch_stats)

    inserted = dry_run ? 0 : insert_batch(ids)
    summary[:inserted] += inserted
    summary[:conflicted] += batch_stats[:eligible] - inserted unless dry_run
  end

  def batch_counts(ids)
    rows = connection.exec_query(batch_counts_sql(ids)).to_a
    scanned = rows.sum { |row| row['count'].to_i }
    skipped_by_reason = rows.each_with_object(SKIP_REASONS.index_with(0)) do |row, counts|
      reason = row['skip_reason']
      counts[reason] = row['count'].to_i if reason.present?
    end
    skipped = skipped_by_reason.values.sum

    {
      scanned: scanned,
      eligible: scanned - skipped,
      skipped: skipped,
      skipped_by_reason: skipped_by_reason
    }
  end

  def merge_batch_counts(batch_stats)
    summary[:scanned] += batch_stats[:scanned]
    summary[:eligible] += batch_stats[:eligible]
    summary[:skipped] += batch_stats[:skipped]

    batch_stats[:skipped_by_reason].each do |reason, count|
      summary[:skipped_by_reason][reason] += count
    end
  end

  def insert_batch(ids)
    connection.exec_query(insert_sql(ids)).rows.size
  end

  def batch_counts_sql(ids)
    <<~SQL.squish
      SELECT #{skip_reason_sql} AS skip_reason, COUNT(*) AS count
      FROM conversation_kanban_states cks
      LEFT JOIN conversations c ON c.id = cks.conversation_id
      LEFT JOIN kanban_boards kb ON kb.id = cks.kanban_board_id
      LEFT JOIN kanban_stages ks ON ks.id = cks.kanban_stage_id
      WHERE cks.id IN (#{quoted_ids(ids)})
      GROUP BY skip_reason
    SQL
  end

  def insert_sql(ids)
    <<~SQL.squish
      INSERT INTO kanban_cards (
        #{insert_columns}
      )
      SELECT
        #{insert_select_values}
      FROM conversation_kanban_states cks
      INNER JOIN conversations c ON c.id = cks.conversation_id
      INNER JOIN kanban_boards kb ON kb.id = cks.kanban_board_id
      INNER JOIN kanban_stages ks ON ks.id = cks.kanban_stage_id
      WHERE cks.id IN (#{quoted_ids(ids)})
        AND c.contact_id IS NOT NULL
        AND c.inbox_id IS NOT NULL
        AND kb.account_id = c.account_id
        AND ks.account_id = c.account_id
        AND ks.kanban_board_id = cks.kanban_board_id
      ON CONFLICT DO NOTHING
      RETURNING id
    SQL
  end

  def insert_columns
    <<~SQL.squish
      account_id, kanban_board_id, kanban_stage_id, contact_id, inbox_id, conversation_id,
      subject, normalized_subject, origin, position, active, created_at, updated_at
    SQL
  end

  def insert_select_values
    <<~SQL.squish
      c.account_id, cks.kanban_board_id, cks.kanban_stage_id, c.contact_id, c.inbox_id, c.id,
      NULL, NULL, 'conversation', cks.position, TRUE, cks.created_at, cks.updated_at
    SQL
  end

  def skip_reason_sql
    <<~SQL.squish
      CASE
        WHEN c.id IS NULL THEN 'missing_conversation'
        WHEN c.contact_id IS NULL THEN 'missing_contact'
        WHEN c.inbox_id IS NULL THEN 'missing_inbox'
        WHEN kb.id IS NULL THEN 'missing_board'
        WHEN ks.id IS NULL THEN 'missing_stage'
        WHEN kb.account_id != c.account_id OR ks.account_id != c.account_id THEN 'account_mismatch'
        WHEN ks.kanban_board_id != cks.kanban_board_id THEN 'stage_board_mismatch'
        ELSE NULL
      END
    SQL
  end

  def quoted_ids(ids)
    ids.map { |id| connection.quote(id) }.join(',')
  end

  def print_summary
    puts 'Kanban cards backfill summary:'
    puts "scanned rows: #{summary[:scanned]}"
    puts "eligible rows: #{summary[:eligible]}"
    puts "inserted rows: #{summary[:inserted]}"
    puts "already migrated/conflicted rows: #{summary[:conflicted]}"
    puts "skipped rows: #{summary[:skipped]}"
    puts "batch size: #{batch_size}"
    puts "dry-run status: #{dry_run}"
    puts 'skipped rows by reason:'

    summary[:skipped_by_reason].each do |reason, count|
      puts "  #{reason}: #{count}"
    end
  end

  def connection
    ActiveRecord::Base.connection
  end

  def sanitize_sql(array)
    ActiveRecord::Base.sanitize_sql_array(array)
  end
end
