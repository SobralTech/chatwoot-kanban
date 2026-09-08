# Ticket 24 — WAHA correlation and operational signals

The WAHA integration now reports every operational condition an administrator
needs through one call: `Waha::Telemetry.emit`. Each signal is written twice —
as a logfmt line on `Rails.logger`, and as an `ActiveSupport::Notifications`
event named `waha.<signal>`. No new gem, store, endpoint or dashboard was
added: an already-configured APM or StatsD subscriber turns the notifications
into metrics, and the notification fires at every severity, so a signal is
still counted when its log line sits below the configured level.

The ad-hoc `Rails.logger` lines that previously covered these paths were
replaced rather than supplemented, so there is exactly one report per event.

## The single identifier

`waha_id` is the **stanza**: the engine's own message identifier with the chat
and direction segments GOWS prefixes onto it stripped off (`Waha::Anchoring.
stanza_of`). It is the one value that follows a message across every entry
point, which is what makes an end-to-end trace possible:

| Where | Signal | `waha_id` |
| --- | --- | --- |
| Live webhook received | `event_received` | `AAA111` |
| Message written | `message_persisted` | `AAA111` |
| Redelivered webhook | `message_deduplicated` (`reason=already_mapped`) | `AAA111` |
| Delivery receipt refused | `ack_ignored` | `AAA111` |
| Outgoing part confirmed | `delivery_confirmed` | `NEW001` |
| Echo of that send | `message_deduplicated` (`reason=chatwoot_echo`) | `NEW001` |
| History item | `message_persisted` / `media_download` | the same stanza the live path would have used |

An outgoing message starts under its pre-generated client id and joins that
namespace at `delivery_confirmed`, which reports the id WhatsApp assigned.

`chat_ref` groups the signals of one chat, but `waha_id` — not `chat_ref` — is
the join key across identity forms: an `@lid` and its resolved phone JID
produce different handles (see Privacy below).

Alongside those, a signal carries `account_id`, `inbox_id`, `channel_id`,
`session`, `message_id`, `conversation_id`, `attempt_id`, `part` and `try`
wherever they apply — the correlation set the ticket asks for.

## Signals

| Signal | Meaning | Distinguished by |
| --- | --- | --- |
| `event_received` | A webhook event entered the pipeline | `event` |
| `event_ignored` | It was not represented | `reason`: `session_mismatch`, `connection_identity_conflict`, `unsupported_event`, and the `Waha::InboundEventPolicy` reasons (`status_broadcast_chat`, `newsletter_chat`, `broadcast_chat`, `groups_disabled`, `group_call`, …) |
| `event_retry_scheduled` / `event_retries_exhausted` | An event is waiting for its base message, or gave up | `reason`, `try` (the backlog depth for that event) |
| `message_persisted` | A new message was written | `direction`, `event` (`message`/`edit`) |
| `message_deduplicated` | The event already existed | `reason`: `already_mapped`, `unique_violation`, `chatwoot_echo` |
| `message_unsupported_type` | The visible fallback was selected | `reason`: the GOWS proto node name |
| `media_download` | One media item's outcome | `outcome`: `success`, `transient`, `terminal`; `scope`: `live`, `history`; `reason`, `kind` |
| `media_backlog_paused` | A chat's media circuit breaker tripped | `pending` |
| `ack_ignored` | A receipt was refused | `reason`: `uncorrelated_failure`, `group_without_participant` |
| `delivery_dispatched` / `delivery_confirmed` | One outgoing part left / was confirmed | `part`, `part_type` |
| `delivery_retry_scheduled` / `delivery_failed` | Transient retry / terminal failure | `error` (class), `confirmed_parts`, `total_parts` |
| `delivery_ambiguous` | A dispatched request's outcome was unknown | `outcome`: `recovered`, `unresolved`, `check_failed` |
| `delivery_released` | The attempt was unclaimed without sending | `reason`: `no_deliverable_parts`, `unresolved_attachment` |
| `delivery_without_idempotency_key` | The engine has no client-defined message id | standing limitation, not an incident |
| `delivery_clock_unavailable` | Redis was unreachable for pacing | `error` |
| `import_started` | A history execution began | `kind`, `chats`, `pending` (the backlog) |
| `import_finished` | It reached a terminal state | `outcome`, `duration_ms`, `imported_messages`, `failed_chats` |
| `import_stalled` | A full page advanced the cursor by nothing | `reason=no_progress`, `cursor_ts` |
| `import_chat_failed` / `import_dispatch_failed` | One chat / the dispatcher failed | `error` (class), `try` |
| `contact_identity_conflict` | Aliases claimed by more than one ContactInbox | `reason`: `multiple_claimants`, `merge_failed` |
| `enrichment_failed` | An optional enrichment failed without blocking the message | `reason`: `mention_name`, `group_participant`, `presence` |

The four conditions the ticket asks to keep separable are separate signals or
separate `reason`/`outcome` values: a divergent session is
`event_ignored reason=session_mismatch`, an unsupported type is
`message_unsupported_type`, no progress is `import_stalled`, and an ambiguous
send is `delivery_ambiguous`.

## Cardinality

`Waha::Telemetry::TAG_KEYS` — `signal`, `event`, `reason`, `outcome`,
`direction`, `kind`, `part_type`, `scope` — are the only fields offered as
metric dimensions, and each is drawn from a closed vocabulary written in this
codebase. Every value is reduced to `[a-z0-9._-]{0,40}` before it is published,
so `event`, whose vocabulary belongs to WAHA rather than to us, cannot be used
by a malformed or hostile payload to invent an arbitrary series.

Everything else — `account_id`, `inbox_id`, `channel_id`, `session`,
`chat_ref`, `waha_id`, `message_id`, `conversation_id`, `attempt_id`,
`execution_id`, `part`, `try`, `duration_ms`, counts — is correlation context.
It is logged and carried on the notification payload, and never used as a
dimension.

## Privacy

- No message body, caption, media URL, filename, contact name, phone number or
  raw JID reaches a signal.
- A chat is published as `chat_ref`: `d-`/`g-` (direct or group, which is
  operational rather than personal) plus 12 hex characters of the SHA-256 of
  the JID, after its phone forms are collapsed (`@s.whatsapp.net`, a
  device-suffixed JID and `@c.us` share one handle). It is not reversible to
  the number. This also removes pre-existing leaks — the ack applier logged the
  raw chat JID, and the mention/participant/presence error paths logged raw
  JIDs.
- **Known limit, measured on live traffic:** an `@lid` does not collapse into
  its phone JID. That mapping lives in `waha_contact_aliases` and resolving it
  would put a database query behind every log line. On a real GOWS session,
  230 of 869 mappings (26%) arrived with `@lid` in the provider id while their
  canonical `chat_jid` was `@c.us`, so those signals carry two handles for one
  chat: the observed form on `event_received`/`ack_ignored`/`media_download`,
  and the canonical one on `message_persisted` and the delivery signals.
  `waha_id` joins them, and the observed form is itself operationally useful —
  it shows which identity form the engine is actually sending.
- `waha_id` is the stanza rather than the full provider id, precisely because
  the provider id embeds the chat JID.
- `session` is included as context: it is operator configuration and the join
  key to the WAHA server's own logs, without which an end-to-end trace is not
  possible. It is never a metric dimension.
- No free-text error message is ever emitted. A failure reports its exception
  class; the text stays where it is already persisted and access-controlled —
  `Message#external_error`, `WahaDeliveryAttempt#last_error`,
  `WahaImportChat#error` and `Channel::Waha#import_state`.
- `message_unsupported_type` names the GOWS proto node key (for example
  `newFangledMessage`) and never any of its values.

## Checked against a live GOWS session

Read-only inspection on 2026-09-08 of a running instance (WAHA
`devlikeapro/waha:latest`, one channel, a completed three-month import spanning
2026-06-10 to 2026-09-08): 869 message mappings, 1457 contact aliases, 532
import chats, 494 incoming and 375 outgoing messages. No writes were made and
the running import was not disturbed.

What it confirmed:

- **The provider id has two real shapes**, and `waha_id` survives both.
  Direct chats are `<direction>_<jid>_<stanza>`; group messages are
  `<direction>_<group>@g.us_<stanza>_<participant>@lid` — four segments, not
  three. `Waha::Anchoring.stanza_of` matched `external_id` on both, and
  `chat_jid_of` matched the canonical `chat_jid` for groups.
- **The stanza is always uppercase hex**, 18/20/22/32 characters, never
  containing `_`. Nothing in the sample can be split by the `_` parsing.
- **Group participants arrive as `@lid`** (164/164), never `@c.us`.
- **No chat fragmentation in the canonical table**: all 511 conversations have
  exactly one distinct `chat_jid`, which is ticket 23's normalization working.
- **`import_state` carries `started_at` and `execution_id`**, so
  `import_finished` can report `duration_ms`; the sampled import completed with
  0 retries and no failed chats.

What it corrected: `chat_ref` was claimed to be identical in every signal about
one chat. It is not, for the `@lid` case above — the limit is now documented
here and pinned by a spec, and the phone forms that *can* be collapsed for free
now are.

Not observable on this instance: no message reached the visible fallback and no
media download failed, so `message_unsupported_type` and the `media_download`
failure outcomes remain covered by fixtures only.

## Prior art

The WAHA app on branch `core` was inspected read-only. Its `JobLoggerWrapper`
idea — bind the correlation once and let every line inherit it — is what
`Waha::Telemetry.emit` and the per-service `emit`/`observe` wrappers do here.
Its `ChatWootErrorReporter`, which posts operational failures into the agent's
conversation, was deliberately not adopted: an administrator's signal does not
belong in a customer thread. Its reliance on BullMQ's own job telemetry has no
equivalent here, which is why the notification seam is the metric contract.

## Enterprise

There is no Enterprise WAHA overlay (`rg -l waha enterprise` returns nothing),
and no model, job, controller or API contract changed, so nothing in
`enterprise/` needed a matching change. `Waha::Telemetry` is plain OSS code with
no plan-specific behaviour; an Enterprise build that wants to route these
signals elsewhere subscribes to `waha.*` like any other subscriber.

## Verification

Final run on 2026-09-08: **345 examples, 0 failures** (250 WAHA service/job
examples, 87 webhook/model/controller/migration examples, 8 Enterprise
message/presenter examples); **24 Ruby files inspected, no RuboCop offenses**;
`git diff --check` clean.

```sh
POSTGRES_DATABASE=chatwoot_test bundle exec rspec spec/services/waha spec/jobs/waha
POSTGRES_DATABASE=chatwoot_test bundle exec rspec \
  spec/jobs/webhooks/waha_events_job_spec.rb spec/jobs/webhooks/waha_events_job_mutations_spec.rb \
  spec/models/channel/waha_spec.rb spec/models/waha_message_mapping_spec.rb \
  spec/models/waha_delivery_attempt_spec.rb spec/models/waha_contact_alias_spec.rb \
  spec/controllers/webhooks/waha_controller_spec.rb \
  spec/controllers/api/v1/accounts/conversations/waha_message_actions_spec.rb \
  spec/jobs/migration/backfill_waha_message_mappings_job_spec.rb
POSTGRES_DATABASE=chatwoot_test bundle exec rspec \
  spec/enterprise/models/message_spec.rb spec/enterprise/presenters/conversations/event_data_presenter_spec.rb
```

`spec/services/waha/telemetry_spec.rb` asserts the notification payloads, never
log wording: the correlation set on a received and persisted message, one
identifier carried from a send through the echo that settles it, deduplication
on redelivery, the privacy rules above, the tag whitelist and its sanitisation,
and the four distinguishable conditions plus media outcomes, import duration and
the pending-event backlog.

Five existing specs asserted the exact wording of the log lines this ticket
replaced (`ack_applier`, `call_event_service`, `contact_resolver`, and two in
`waha_events_job_mutations`). They now read the signal payload instead, which is
the decoupling the ticket asks for. `WahaSpecHelpers#capture_waha_signals` is
the shared seam.
