class KanbanCards::ImportExistingConversationsService
  BATCH_SIZE = 1000
  GROUP_IDENTIFIER_PATTERN = '%@g.us%'.freeze

  def initialize(account:, kanban_board:, ignore_groups: false)
    @account = account
    @kanban_board = kanban_board
    @ignore_groups = ActiveModel::Type::Boolean.new.cast(ignore_groups)
    @summary = summary_hash
  end

  def perform!
    return summary unless default_stage

    eligible_conversations.in_batches(of: BATCH_SIZE) do |batch|
      import_batch(batch)
    end

    summary
  end

  def estimated_count
    return 0 unless default_stage

    eligible_conversations.count
  end

  private

  attr_reader :account, :kanban_board, :ignore_groups, :summary

  def import_batch(batch)
    reactivated_count = KanbanCard.connection.exec_query(reactivate_sql(batch)).rows.length
    inserted_count = KanbanCard.connection.exec_query(insert_sql(batch)).rows.length
    summary[:reactivated] += reactivated_count
    summary[:created] += inserted_count
  end

  def reactivate_sql(batch)
    now = KanbanCard.connection.quote(Time.current)
    board_id = KanbanCard.connection.quote(kanban_board.id)
    stage_id = KanbanCard.connection.quote(default_stage.id)

    <<~SQL.squish
      #{reactivation_cte_sql(batch, board_id)}
      UPDATE #{KanbanCard.quoted_table_name}
      SET #{reactivation_update_sql(stage_id, now)}
      FROM ranked_cards
      WHERE #{KanbanCard.quoted_table_name}.id = ranked_cards.id
      RETURNING #{KanbanCard.quoted_table_name}.id
    SQL
  end

  def reactivation_cte_sql(batch, board_id)
    <<~SQL.squish
      WITH batch_conversations AS (#{batch.select(:id).to_sql}),
      ranked_cards AS (
        SELECT
          #{KanbanCard.quoted_table_name}.id,
          (#{max_position_sql}) + ROW_NUMBER() OVER (ORDER BY #{KanbanCard.quoted_table_name}.id) AS next_position
        FROM #{KanbanCard.quoted_table_name}
        INNER JOIN batch_conversations ON batch_conversations.id = #{KanbanCard.quoted_table_name}.conversation_id
        WHERE #{KanbanCard.quoted_table_name}.kanban_board_id = #{board_id}
          AND #{KanbanCard.quoted_table_name}.origin = 'conversation'
          AND #{KanbanCard.quoted_table_name}.active = FALSE
      )
    SQL
  end

  def reactivation_update_sql(stage_id, timestamp)
    [
      'active = TRUE',
      "kanban_stage_id = #{stage_id}",
      'position = ranked_cards.next_position',
      "stage_entered_at = #{timestamp}",
      "updated_at = #{timestamp}"
    ].join(', ')
  end

  def insert_sql(batch)
    <<~SQL.squish
      INSERT INTO #{KanbanCard.quoted_table_name}
        (#{insert_columns.join(', ')})
      #{insert_select_sql(batch)}
      ON CONFLICT (kanban_board_id, conversation_id, inbox_id, normalized_subject)
        WHERE origin = 'conversation' AND conversation_id IS NOT NULL AND normalized_subject IS NOT NULL
        DO NOTHING
      RETURNING id
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
               .open
               .where(account_id: account.id)
               .where.not(contact_id: nil)
               .where.not(inbox_id: nil)
               .where("NOT EXISTS (#{active_card_relation.to_sql})")
               .order(:id)

    relation = relation.where(inbox_id: allowed_inbox_ids) if kanban_board.selected_inboxes?
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

  def allowed_inbox_ids
    @allowed_inbox_ids ||= kanban_board.kanban_board_inboxes.pluck(:inbox_id)
  end

  def active_card_relation
    KanbanCard.conversation
              .active
              .where(kanban_board_id: kanban_board.id)
              .where('kanban_cards.conversation_id = conversations.id')
              .select('1')
  end

  def default_stage
    @default_stage ||= kanban_board.kanban_stages.active.ordered.first
  end

  def summary_hash
    {
      created: 0,
      reactivated: 0
    }
  end
end
