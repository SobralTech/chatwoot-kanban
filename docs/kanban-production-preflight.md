# Kanban Production Preflight

Use this runbook before rolling Kanban cards into an existing upgraded Chatwoot production database. Do not run automatic data-modifying scripts from this document; investigate and resolve unexpected rows manually.

## Preconditions

- Take and verify a production database backup before schema changes.
- Rehearse the rollout on a staging restore or production-like database copy.
- Schedule a maintenance window for schema changes and operational validation.
- Confirm Sidekiq is healthy before starting: queues are draining, retries are understood, and workers are processing jobs.
- Confirm the PostgreSQL version and `pgvector` extension on the target database.

```sh
psql "${DATABASE_URL}" -c "SELECT version();"
psql "${DATABASE_URL}" -c "SELECT extname, extversion FROM pg_extension WHERE extname = 'vector';"
```

## Preflight SQL

Run these read-only queries against the target database before migrations. Any returned row needs manual review before continuing.

```sql
-- Duplicate conversation-origin cards.
SELECT kanban_board_id, conversation_id, COUNT(*) AS card_count, ARRAY_AGG(id ORDER BY id) AS card_ids
FROM kanban_cards
WHERE origin = 'conversation'
  AND conversation_id IS NOT NULL
GROUP BY kanban_board_id, conversation_id
HAVING COUNT(*) > 1
ORDER BY kanban_board_id, conversation_id;

-- Duplicate active manual opportunities.
SELECT kanban_board_id, contact_id, inbox_id, normalized_subject, COUNT(*) AS card_count, ARRAY_AGG(id ORDER BY id) AS card_ids
FROM kanban_cards
WHERE active = TRUE
  AND origin = 'manual'
  AND normalized_subject IS NOT NULL
GROUP BY kanban_board_id, contact_id, inbox_id, normalized_subject
HAVING COUNT(*) > 1
ORDER BY kanban_board_id, contact_id, inbox_id, normalized_subject;

-- Invalid card references/account mismatches.
SELECT kc.id, kc.account_id, kc.kanban_board_id, kc.kanban_stage_id, kc.contact_id, kc.inbox_id, kc.conversation_id,
       kb.account_id AS board_account_id, ks.account_id AS stage_account_id, ks.kanban_board_id AS stage_board_id,
       contacts.account_id AS contact_account_id, inboxes.account_id AS inbox_account_id, conversations.account_id AS conversation_account_id,
       conversations.contact_id AS conversation_contact_id, conversations.inbox_id AS conversation_inbox_id
FROM kanban_cards kc
LEFT JOIN kanban_boards kb ON kb.id = kc.kanban_board_id
LEFT JOIN kanban_stages ks ON ks.id = kc.kanban_stage_id
LEFT JOIN contacts ON contacts.id = kc.contact_id
LEFT JOIN inboxes ON inboxes.id = kc.inbox_id
LEFT JOIN conversations ON conversations.id = kc.conversation_id
WHERE kb.id IS NULL
   OR ks.id IS NULL
   OR contacts.id IS NULL
   OR inboxes.id IS NULL
   OR kb.account_id IS DISTINCT FROM kc.account_id
   OR ks.account_id IS DISTINCT FROM kc.account_id
   OR contacts.account_id IS DISTINCT FROM kc.account_id
   OR inboxes.account_id IS DISTINCT FROM kc.account_id
   OR ks.kanban_board_id IS DISTINCT FROM kc.kanban_board_id
   OR (kc.origin = 'conversation' AND conversations.id IS NULL)
   OR (kc.conversation_id IS NOT NULL AND conversations.account_id IS DISTINCT FROM kc.account_id)
   OR (kc.conversation_id IS NOT NULL AND conversations.contact_id IS DISTINCT FROM kc.contact_id)
   OR (kc.conversation_id IS NOT NULL AND conversations.inbox_id IS DISTINCT FROM kc.inbox_id)
ORDER BY kc.id;

-- Invalid legacy-state references.
SELECT cks.id, cks.account_id, cks.conversation_id, cks.kanban_board_id, cks.kanban_stage_id,
       conversations.account_id AS conversation_account_id, kb.account_id AS board_account_id,
       ks.account_id AS stage_account_id, ks.kanban_board_id AS stage_board_id
FROM conversation_kanban_states cks
LEFT JOIN conversations ON conversations.id = cks.conversation_id
LEFT JOIN kanban_boards kb ON kb.id = cks.kanban_board_id
LEFT JOIN kanban_stages ks ON ks.id = cks.kanban_stage_id
WHERE conversations.id IS NULL
   OR kb.id IS NULL
   OR ks.id IS NULL
   OR conversations.contact_id IS NULL
   OR conversations.inbox_id IS NULL
   OR cks.account_id IS DISTINCT FROM conversations.account_id
   OR kb.account_id IS DISTINCT FROM conversations.account_id
   OR ks.account_id IS DISTINCT FROM conversations.account_id
   OR ks.kanban_board_id IS DISTINCT FROM cks.kanban_board_id
ORDER BY cks.id;

-- Active cards in inactive stages.
SELECT kc.id, kc.kanban_board_id, kc.kanban_stage_id, kc.position
FROM kanban_cards kc
INNER JOIN kanban_stages ks ON ks.id = kc.kanban_stage_id
WHERE kc.active = TRUE
  AND ks.active = FALSE
ORDER BY kc.kanban_board_id, kc.kanban_stage_id, kc.position, kc.id;

-- Invalid active position ordering.
WITH ordered_cards AS (
  SELECT id, kanban_board_id, kanban_stage_id, position,
         ROW_NUMBER() OVER (PARTITION BY kanban_board_id, kanban_stage_id ORDER BY position ASC, created_at ASC, id ASC) AS expected_position
  FROM kanban_cards
  WHERE active = TRUE
)
SELECT id, kanban_board_id, kanban_stage_id, position, expected_position
FROM ordered_cards
WHERE position IS DISTINCT FROM expected_position
ORDER BY kanban_board_id, kanban_stage_id, expected_position;

-- Duplicate active positions.
SELECT kanban_board_id, kanban_stage_id, position, COUNT(*) AS card_count, ARRAY_AGG(id ORDER BY created_at ASC, id ASC) AS card_ids
FROM kanban_cards
WHERE active = TRUE
GROUP BY kanban_board_id, kanban_stage_id, position
HAVING COUNT(*) > 1
ORDER BY kanban_board_id, kanban_stage_id, position;

-- Boards with automation enabled but no active stage.
SELECT kb.id, kb.account_id, kb.name
FROM kanban_boards kb
LEFT JOIN kanban_stages ks ON ks.kanban_board_id = kb.id AND ks.active = TRUE
WHERE kb.active = TRUE
  AND kb.auto_create_cards_from_conversations = TRUE
GROUP BY kb.id, kb.account_id, kb.name
HAVING COUNT(ks.id) = 0
ORDER BY kb.account_id, kb.id;

-- Duplicate board names across all rows.
SELECT account_id, name, COUNT(*) AS board_count, ARRAY_AGG(id ORDER BY id) AS board_ids
FROM kanban_boards
GROUP BY account_id, name
HAVING COUNT(*) > 1
ORDER BY account_id, name;

-- Duplicate stage names across all rows.
SELECT kanban_board_id, name, COUNT(*) AS stage_count, ARRAY_AGG(id ORDER BY id) AS stage_ids
FROM kanban_stages
GROUP BY kanban_board_id, name
HAVING COUNT(*) > 1
ORDER BY kanban_board_id, name;
```

## Migration Sequence

1. Run the preflight SQL against the target database using placeholders such as `${DATABASE_URL}`, `${PGHOST}`, `${PGDATABASE}`, and `${PGUSER}`.
2. Resolve unexpected rows manually. Re-run the affected query until it returns no unexpected rows.
3. Run migrations with the normal production deploy process.
4. Run `DRY_RUN=true bundle exec rake kanban_cards:backfill`.
5. Review skipped and conflicted counts. Investigate non-zero unexpected counts before writing data.
6. Run `bundle exec rake kanban_cards:backfill`.
7. Run `bundle exec rake kanban_cards:audit_parity`.
8. Validate Sidekiq after the backfill: queues are draining, retry/dead sets are understood, and workers are processing jobs.
9. Run the browser smoke test matrix below.

## Smoke Test Matrix

- Board list and board show load for an account with Kanban enabled.
- Stage pagination works and `Load more` appends additional cards without duplicates.
- Manual card creation creates one active manual opportunity with the expected title and placement.
- Automatic card creation from `conversation.created` creates one conversation-origin card on an automation-enabled board.
- Card modal shows title, start/due dates, labels, and notes correctly.
- Open conversation action navigates to the expected conversation.
- Same-stage drag updates ordering and persists after refresh.
- Cross-stage drag moves the card, updates ordering in both stages, and persists after refresh.
- Card delete deactivates the card and closes/removes it from the active board view.
- Inactive board and inactive stage rejection prevents creating or moving active cards into inactive containers.

## Rollback Notes

- Keep `conversation_kanban_states`, its model, the sync service, the retained switch column, and the `kanban_cards` rake tasks during the rollback window.
- Current runtime no longer dual-writes legacy states.
- After production mutations, redeploying old code alone may expose stale legacy ordering/data.
- The safest rollback after live writes is a database restore or an explicit reverse-reconciliation procedure.
- Do not drop legacy database artifacts until the rollback window closes.

## Known Limitation

Fresh migration-chain validation is currently blocked before the Kanban migrations by:

```text
20231211010807_add_cached_labels_list
uninitialized constant ActsAsTaggableOn::Taggable::Cache
```

An existing upgraded production database is the intended rollout path. Investigate fresh-install compatibility separately before supporting clean installs.
