# frozen_string_literal: true

# rubocop:disable Style/OneClassPerFile

namespace :kanban_cards do
  desc 'Backfill kanban_cards from conversation_kanban_states'
  task backfill: :environment do
    KanbanCardsBackfill.new.run
  end

  desc 'Audit parity between conversation_kanban_states and conversation-origin kanban_cards'
  task audit_parity: :environment do
    exit(false) unless KanbanCardsParityAudit.new.run
  end
end

class KanbanCardsParityAudit
  SUMMARY_KEYS = %i[
    legacy_rows
    matching_rows
    missing_mirror
    duplicate_mirror
    field_mismatch
    standalone_conversation_cards
    inactive_mirror_for_active_legacy
  ].freeze

  DRIFT_KEYS = SUMMARY_KEYS.without(:legacy_rows, :matching_rows, :standalone_conversation_cards).freeze

  MISMATCH_FIELDS = %w[
    account_id
    kanban_board_id
    kanban_stage_id
    contact_id
    inbox_id
    position
    active
    origin
    normalized_subject
  ].freeze

  EXAMPLE_LIMIT = 10

  def run
    summary = fetch_summary
    mismatches_by_field = fetch_mismatches_by_field

    print_summary(summary, mismatches_by_field)
    print_examples

    drift_free?(summary)
  end

  private

  def fetch_summary
    row = connection.exec_query(summary_sql).first || {}

    SUMMARY_KEYS.index_with { |key| row[key.to_s].to_i }
  end

  def fetch_mismatches_by_field
    row = connection.exec_query(mismatches_by_field_sql).first || {}

    MISMATCH_FIELDS.index_with { |field| row[field].to_i }
  end

  def print_summary(summary, mismatches_by_field)
    puts 'Kanban cards parity audit summary:'
    SUMMARY_KEYS.each { |key| puts "#{key}: #{summary[key]}" }
    puts 'field_mismatch_by_field:'
    MISMATCH_FIELDS.each { |field| puts "  #{field}: #{mismatches_by_field[field]}" }
  end

  def print_examples
    puts 'examples:'
    example_queries.each do |category, sql|
      ids = connection.select_values(sql)
      puts "  #{category}: #{ids.join(', ')}" if ids.present?
    end
  end

  def drift_free?(summary)
    summary.values_at(*DRIFT_KEYS).all?(&:zero?)
  end

  def summary_sql
    <<~SQL.squish
      WITH legacy_matches AS (#{legacy_matches_sql})
      SELECT
        COUNT(*) AS legacy_rows,
        COUNT(*) FILTER (WHERE mirror_count = 1 AND fields_match) AS matching_rows,
        COUNT(*) FILTER (WHERE mirror_count = 0) AS missing_mirror,
        COUNT(*) FILTER (WHERE mirror_count > 1) AS duplicate_mirror,
        COUNT(*) FILTER (WHERE mirror_count = 1 AND NOT fields_match) AS field_mismatch,
        (#{standalone_conversation_cards_count_sql}) AS standalone_conversation_cards,
        COUNT(*) FILTER (WHERE active_mirror_count = 0 AND inactive_mirror_count > 0) AS inactive_mirror_for_active_legacy
      FROM legacy_matches
    SQL
  end

  def mismatches_by_field_sql
    <<~SQL.squish
      WITH legacy_matches AS (#{legacy_matches_sql})
      SELECT
        #{mismatch_field_selects}
      FROM legacy_matches
      WHERE mirror_count = 1
    SQL
  end

  def mismatch_field_selects
    MISMATCH_FIELDS.map do |field|
      "COUNT(*) FILTER (WHERE #{field}_mismatch) AS #{field}"
    end.join(', ')
  end

  def legacy_matches_sql
    <<~SQL.squish
      SELECT
        cks.id AS legacy_id,
        COUNT(kc.id) AS mirror_count,
        COUNT(kc.id) FILTER (WHERE kc.active = TRUE) AS active_mirror_count,
        COUNT(kc.id) FILTER (WHERE kc.active = FALSE) AS inactive_mirror_count,
        #{field_mismatch_selects},
        #{fields_match_sql} AS fields_match
      FROM conversation_kanban_states cks
      LEFT JOIN conversations c ON c.id = cks.conversation_id
      LEFT JOIN kanban_cards kc
        ON kc.kanban_board_id = cks.kanban_board_id
       AND kc.conversation_id = cks.conversation_id
       AND kc.origin = 'conversation'
      GROUP BY cks.id, c.account_id, c.contact_id, c.inbox_id
    SQL
  end

  def field_mismatch_selects
    field_comparisons.map do |field, comparison|
      "BOOL_OR(#{comparison}) AS #{field}_mismatch"
    end.join(', ')
  end

  def fields_match_sql
    field_comparisons.values.map { |comparison| "NOT BOOL_OR(#{comparison})" }.join(' AND ')
  end

  def field_comparisons
    {
      'account_id' => 'kc.account_id IS DISTINCT FROM c.account_id',
      'kanban_board_id' => 'kc.kanban_board_id IS DISTINCT FROM cks.kanban_board_id',
      'kanban_stage_id' => 'kc.kanban_stage_id IS DISTINCT FROM cks.kanban_stage_id',
      'contact_id' => 'kc.contact_id IS DISTINCT FROM c.contact_id',
      'inbox_id' => 'kc.inbox_id IS DISTINCT FROM c.inbox_id',
      'position' => 'kc.position IS DISTINCT FROM cks.position',
      'active' => 'kc.active IS DISTINCT FROM TRUE',
      'origin' => "kc.origin IS DISTINCT FROM 'conversation'",
      'normalized_subject' => 'kc.normalized_subject IS DISTINCT FROM NULL'
    }
  end

  def standalone_conversation_cards_count_sql
    <<~SQL.squish
      SELECT COUNT(*)
      FROM kanban_cards kc
      LEFT JOIN conversation_kanban_states cks
        ON cks.kanban_board_id = kc.kanban_board_id
       AND cks.conversation_id = kc.conversation_id
      WHERE kc.active = TRUE
        AND kc.origin = 'conversation'
        AND cks.id IS NULL
    SQL
  end

  def example_queries
    {
      missing_mirror: example_sql('mirror_count = 0'),
      duplicate_mirror: example_sql('mirror_count > 1'),
      field_mismatch: example_sql('mirror_count = 1 AND NOT fields_match'),
      inactive_mirror_for_active_legacy: example_sql('active_mirror_count = 0 AND inactive_mirror_count > 0'),
      standalone_conversation_cards: standalone_conversation_cards_examples_sql
    }
  end

  def example_sql(condition)
    <<~SQL.squish
      WITH legacy_matches AS (#{legacy_matches_sql})
      SELECT legacy_id
      FROM legacy_matches
      WHERE #{condition}
      ORDER BY legacy_id
      LIMIT #{EXAMPLE_LIMIT}
    SQL
  end

  def standalone_conversation_cards_examples_sql
    <<~SQL.squish
      SELECT kc.id
      FROM kanban_cards kc
      LEFT JOIN conversation_kanban_states cks
        ON cks.kanban_board_id = kc.kanban_board_id
       AND cks.conversation_id = kc.conversation_id
      WHERE kc.active = TRUE
        AND kc.origin = 'conversation'
        AND cks.id IS NULL
      ORDER BY kc.id
      LIMIT #{EXAMPLE_LIMIT}
    SQL
  end

  def connection
    ActiveRecord::Base.connection
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

# rubocop:enable Style/OneClassPerFile
