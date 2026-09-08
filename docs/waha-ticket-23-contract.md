# Ticket 23 — canonical message correlation

The WAHA integration now reads message identity from `waha_message_mappings`, scoped by channel and chat. Incoming messages, history, replies, edit families, reactions, revocations, media retrieval and delivery receipts no longer look up `Message.source_id`. Outgoing confirmation writes the canonical mapping and the per-part delivery checkpoint atomically. The old best-effort writer and pre-multipart confirmation fallback are removed.

`provider_id` preserves the complete GOWS identifier used by provider endpoints. `anchor_message_id` links edit mirrors to the native original message. Deletion reads every confirmed mapping in part order; replies, edits and reactions use the first part. Public `source_id` remains available through serialization from canonical data, without a second database write. ContactInbox identifiers remain part of the native contact contract and are not retired by this ticket.

## Prerequisites and reference

All six prerequisite commits are ancestors of the implementation branch: ticket 12 `d9ad5db85`, 13 `1bcab6aca`, 14 `1c844d00d`, 15 `0afc26940`, 16 `83e06a29f`, and 17 `7ca63f188`.

The WAHA app on branch `core` was inspected read-only (`MessageMappingService`, `MessageMappingRepository`, and scheduled message cleanup). Its ID-only lookup, single-row multipart reads and 365-day expiry were not adopted. Native Chatwoot messages remain the presentation model. Enterprise source and the shared message model/presenter tests were checked; no Enterprise WAHA override exists. The shared serializer keeps the same public field, following the [Enterprise development guidelines](https://chatwoot.help/hc/handbook/articles/developing-enterprise-edition-features-38).

## Deployment and historical data

Stop old application workers and webhook processing before migrating, then start the new version after the migration commits. The contract migration executes backfill synchronously and removes the obsolete stanza/edit JSON lookup indexes. Do not roll out old and new writers concurrently. New writes no longer populate the retired fields, so schema rollback is explicitly irreversible; reverting the application requires a pre-contract snapshot or a separate reverse data migration.

The backfill preserves raw provider IDs, maps old edit families, and converts dispatched/sent pre-multipart attempts into delivery parts. Undispatched attempts remain available to normal multipart planning. Confirmed part IDs can recover a missing message correlation. The historical database fields are retained as forensic input for the repeatable backfill, not as runtime fallback.

Ambiguities are reported with message/inbox IDs and reasons in the backfill return value and logs:

- Missing chat or stanza.
- Disagreement between provider chat and conversation without known alias evidence.
- Multiple historical messages claiming the same channel/chat/event identity.
- Missing or ambiguous edit anchor.
- Dispatched attempts without a correlation ID, requiring reconciliation.
- A confirmed delivery part conflicting with another message.

Conflicting mappings are quarantined with `ambiguous: true`; ordinary lookups and actions cannot choose that claimant. Conflicting canonical matches across aliases raise an explicit ambiguity error, including during history indexing. No ambiguous rows are deleted or automatically merged. Mapping retention has no age limit, and soft deletion/revocation retains identities for later deduplication and references.

Read-only inspection of the configured development database on 2026-09-08 found **0 WAHA channels and 0 WAHA messages**. There were no local legacy cases to enumerate. This is not an audit of production. A connected GOWS end-to-end production release check remains an operator step; automated tests exercise the GOWS payload contract and simulated provider boundary.

## Verification

Final verification on 2026-09-08: **364 examples, 0 failures** (353 flow/API/Enterprise examples plus 11 channel/alias examples); **43 Ruby files inspected, no RuboCop offenses**; `git diff --check` clean. Ruby source was held unchanged throughout the final test runs because this repository enables class reloading in the test environment.

The suite includes WAHA services, live/history concurrency, multipart retries, webhook mutations, the migration, native message APIs, WAHA action requests, and shared Enterprise message/presenter behavior. Migration regressions cover conflicting historical claimants, missing identity, provider/chat mismatch, preserved edit/reply context after clearing legacy values, in-flight echoes, confirmed multipart parts, missing message correlation and old revoked identities. API tests prove that serialized IDs and edit/reaction/delete actions work with an empty legacy column.

Run with the repository Ruby/Node versions and a dedicated test database:

```sh
POSTGRES_DATABASE=chatwoot_test bundle exec rspec \
  spec/services/waha spec/jobs/waha \
  spec/jobs/webhooks/waha_events_job_spec.rb \
  spec/jobs/webhooks/waha_events_job_mutations_spec.rb \
  spec/models/waha_message_mapping_spec.rb spec/models/waha_delivery_attempt_spec.rb \
  spec/models/channel/waha_spec.rb spec/models/waha_contact_alias_spec.rb \
  spec/jobs/migration/backfill_waha_message_mappings_job_spec.rb \
  spec/controllers/api/v1/accounts/conversations/messages_controller_spec.rb \
  spec/controllers/api/v1/accounts/conversations/waha_message_actions_spec.rb \
  spec/controllers/webhooks/waha_controller_spec.rb \
  spec/enterprise/models/message_spec.rb \
  spec/enterprise/presenters/conversations/event_data_presenter_spec.rb
```

RuboCop checks all changed Ruby source/specs and the new migration. `db/schema.rb` is the generated schema. No JavaScript source changed.

The following search returns no removed runtime APIs in either tree:

```sh
rg -n 'Waha::Anchoring\.(by_stanza|anchor_source_id)|WahaMessageMapping\.record!|legacy_conversation_message|confirm_legacy_sent!' app enterprise
```

The following broader search returns only `app/jobs/migration/backfill_waha_message_mappings_job.rb`, the explicit one-time/administrative legacy reader:

```sh
rg -n 'edit_of|STANZA_SQL|by_stanza' app enterprise -g '*.rb'
```

Remaining `source_id` lookups in WAHA contact resolution address ContactInbox records, not message mappings. The generic reply builder branches to canonical WAHA resolution before its non-WAHA source lookup. The outgoing service overrides the base channel-origin guard with canonical mapping/attempt state.
