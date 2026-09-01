class KanbanCards::ImportExistingConversationsService
  BATCH_SIZE = 1000
  GROUP_IDENTIFIER_PATTERN = '%@g.us%'.freeze

  def initialize(account:, kanban_board:, ignore_groups: false, entry_rule: nil)
    @account = account
    @kanban_board = kanban_board
    @ignore_groups = ActiveModel::Type::Boolean.new.cast(ignore_groups)
    @entry_rule = entry_rule
    @summary = summary_hash
  end

  def perform!
    return summary unless default_stage

    sql_conversations = sql_filtered_conversations
    (sql_conversations || eligible_conversations).in_batches(of: BATCH_SIZE) do |batch|
      batch = batch.where(id: matching_conversation_ids(batch)) unless sql_conversations
      import_batch(batch)
    end

    summary
  end

  def estimated_count
    return 0 unless default_stage

    conversations = sql_filtered_conversations
    return conversations.count if conversations

    count = 0
    eligible_conversations.in_batches(of: BATCH_SIZE) { |batch| count += matching_conversation_ids(batch).size }
    count
  end

  private

  attr_reader :account, :kanban_board, :ignore_groups, :entry_rule, :summary

  # A nil result means a future condition is not supported by the SQL filter yet. The
  # matcher remains the compatibility path, so adding a condition cannot broaden imports.
  def sql_filtered_conversations
    return @sql_filtered_conversations if defined?(@sql_filtered_conversations)

    @sql_filtered_conversations = KanbanBoardEntryRules::ConversationFilter.apply(eligible_conversations, entry_rule)
  end

  def matching_conversation_ids(batch)
    batch.select(:id, :assignee_id, :team_id, :priority, :cached_label_list).filter_map do |conversation|
      conversation.id if KanbanBoardEntryRules::Matcher.match?(conversation, entry_rule)
    end
  end

  def import_batch(batch)
    inserted_rows = KanbanCard.transaction do
      rows = KanbanCard.connection.exec_query(insert_sql(batch)).to_a
      record_card_created_events(rows)
      rows
    end

    summary[:created] += inserted_rows.length
  end

  # Retroactive import deliberately does not fire `card_created` automations. A backfill
  # of every existing conversation would hand a send_message rule the whole contact base
  # at once, which is the failure the automation guardrails exist to prevent. Cards
  # created from new conversations still trigger normally.
  #
  # Stays bulk: the events are built from the INSERT ... RETURNING rows, so an
  # import costs two statements per batch instead of one per imported card.
  def record_card_created_events(rows)
    return if rows.empty?

    recorded_at = Time.current
    # rubocop:disable Rails/SkipsModelValidations
    KanbanCardEvent.insert_all(
      rows.map do |row|
        {
          account_id: row['account_id'],
          kanban_card_id: row['id'],
          kanban_board_id: row['kanban_board_id'],
          event_type: 'card_created',
          metadata: KanbanCards::RecordEventService.card_created_metadata(row),
          created_at: recorded_at
        }
      end
    )
    # rubocop:enable Rails/SkipsModelValidations
  end

  def insert_sql(batch)
    <<~SQL.squish
      INSERT INTO #{KanbanCard.quoted_table_name}
        (#{insert_columns.join(', ')})
      #{insert_select_sql(batch)}
      ON CONFLICT (kanban_board_id, conversation_id, inbox_id, normalized_subject)
        WHERE origin = 'conversation' AND conversation_id IS NOT NULL AND normalized_subject IS NOT NULL
        DO NOTHING
      RETURNING id, account_id, kanban_board_id, kanban_stage_id, conversation_id, origin
    SQL
  end

  def insert_columns
    %w[
      account_id
      kanban_board_id
      kanban_stage_id
      contact_id
      inbox_id
      conversation_id
      subject
      normalized_subject
      origin
      position
      active
      stage_entered_at
      created_at
      updated_at
    ]
  end

  def insert_select_sql(batch)
    now = KanbanCard.connection.quote(Time.current)
    board_id = KanbanCard.connection.quote(kanban_board.id)
    stage_id = KanbanCard.connection.quote(default_stage.id)
    batch_sql = batch.select(:id).to_sql

    <<~SQL.squish
      SELECT #{insert_select_values(board_id, stage_id, now).join(', ')}
      FROM conversations
      INNER JOIN contacts ON contacts.id = conversations.contact_id
      INNER JOIN inboxes ON inboxes.id = conversations.inbox_id
      WHERE conversations.id IN (#{batch_sql})
    SQL
  end

  def insert_select_values(board_id, stage_id, timestamp)
    [
      'conversations.account_id',
      board_id,
      stage_id,
      'conversations.contact_id',
      'conversations.inbox_id',
      'conversations.id',
      default_subject_sql,
      "LOWER(REGEXP_REPLACE(TRIM(#{default_subject_sql}), '\\s+', ' ', 'g'))",
      "'conversation'",
      "(#{max_position_sql}) + ROW_NUMBER() OVER (ORDER BY conversations.id)",
      'TRUE',
      timestamp,
      timestamp,
      timestamp
    ]
  end

  def default_subject_sql
    <<~SQL.squish
      CONCAT(
        COALESCE(NULLIF(contacts.name, ''), CONCAT('Contact #', contacts.id)),
        ' - ',
        COALESCE(NULLIF(inboxes.name, ''), CONCAT('Inbox #', inboxes.id))
      )
    SQL
  end

  def max_position_sql
    KanbanCard
      .where(kanban_board_id: kanban_board.id, kanban_stage_id: default_stage.id, active: true)
      .select('COALESCE(MAX(position), 0)')
      .to_sql
  end

  def eligible_conversations
    relation = Conversation
               .where(account_id: account.id)
               .where.not(contact_id: nil)
               .where.not(inbox_id: nil)
               .where("NOT EXISTS (#{existing_card_relation.to_sql})")
               .order(:id)

    relation = relation.where(inbox_id: allowed_inbox_ids) if allowed_inbox_ids
    relation = exclude_group_conversations(relation) if ignore_groups
    relation
  end

  def exclude_group_conversations(relation)
    relation
      .left_joins(:contact, :contact_inbox)
      .where.not('LOWER(COALESCE(conversations.identifier, ?)) LIKE ?', '', GROUP_IDENTIFIER_PATTERN)
      .where.not('LOWER(COALESCE(contacts.identifier, ?)) LIKE ?', '', GROUP_IDENTIFIER_PATTERN)
      .where.not('LOWER(COALESCE(contacts.phone_number, ?)) LIKE ?', '', GROUP_IDENTIFIER_PATTERN)
      .where.not('LOWER(COALESCE(contact_inboxes.source_id, ?)) LIKE ?', '', GROUP_IDENTIFIER_PATTERN)
  end

  # nil means "do not narrow": either the chosen rule covers every inbox, or no rule was
  # chosen and the board's own derived scope already decides what is importable.
  def allowed_inbox_ids
    return @allowed_inbox_ids if defined?(@allowed_inbox_ids)

    @allowed_inbox_ids =
      if entry_rule.present?
        entry_rule.all_inboxes? ? nil : entry_rule.inbox_ids
      else
        kanban_board.derived_inbox_scope.then { |scope| scope.fetch(:mode) == 'all_inboxes' ? nil : scope.fetch(:inbox_ids) }
      end
  end

  def existing_card_relation
    KanbanCard.conversation
              .where(kanban_board_id: kanban_board.id)
              .where('kanban_cards.conversation_id = conversations.id')
              .select('1')
  end

  def default_stage
    @default_stage ||= kanban_board.kanban_stages.active.ordered.first
  end

  def summary_hash
    { created: 0 }
  end
end
