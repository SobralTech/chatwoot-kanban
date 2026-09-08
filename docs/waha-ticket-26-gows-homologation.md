# WAHA ticket 26 — GOWS homologation record

Homologation of the hardened WAHA integration against a real, production
WhatsApp account on the GOWS engine, plus the Enterprise-overlay review that
gates the release. Run on 2026-09-08, 19:52–21:00 UTC.

## Homologated versions

| Component | Value |
| --- | --- |
| WAHA | `2026.8.2` |
| Engine | `GOWS` (`WHATSAPP_DEFAULT_ENGINE=GOWS`, `WAHA_GOWS_SOCKET=/tmp/gows.sock`) |
| Tier | `CORE` (single session per server) |
| Platform | `linux/x64`, no browser |
| Chatwoot | this branch, Ruby 3.4.4, Rails 7.1.5.2, PostgreSQL 16 |
| Session | `7433-chatwoot-debug-test`, number `558892627433`, LID `107932746309803@lid`, device JID `558892627433:51@s.whatsapp.net` |
| Account under test | 844 chats, 32 groups, ~31.7k messages imported |

Subscribed webhook events (`Waha::SessionService::WEBHOOK_EVENTS`): `message.any`,
`message.ack`, `message.ack.group`, `message.edited`, `message.revoked`,
`message.reaction`, `poll.vote`, `session.status`.

## Scenario matrix

| # | Scenario | Chat | Result |
| --- | --- | --- | --- |
| 1 | Live inbound DM | real contact `558899615553@c.us` | Contact, name and phone resolved; conversation created; message mirrored once |
| 2 | Live inbound group | real groups | Structured participant (`sender_name`, `participant_jid`, `participant_phone`) on the message, never prefixed into the body |
| 3 | Inbound reply | real group | `in_reply_to` + `in_reply_to_external_id`; snapshot when the original predates the inbox |
| 4 | Inbound edit | real group | Edit mirror `… [✏️ Editada]`, original struck through |
| 5 | Inbound reaction | real group | Reaction chip on the current family member |
| 6 | Inbound mention | real group | `@Tião Liberato` resolved to a readable name |
| 7 | Inbound media | real groups | Image/audio/sticker attached from the live download |
| 8 | Outbound from Chatwoot (DM + group) | test chats | Delivered; echo suppressed; exactly one message per send |
| 9 | Outbound multipart | DM | text + 3 attachments → 4 ordered parts, one `client_message_id`/`external_id` per part, 4 mappings, 1 Chatwoot message |
| 10 | Own message sent by another API | DM + group | Mirrored as outgoing with the `Enviado pelo WhatsApp` label, not deduplicated |
| 11 | Reply from Chatwoot | DM + group | `reply_to` resolved to the family anchor |
| 12 | Edit from Chatwoot | DM + group | Round-trips through `message.edited`; agent attribution preserved |
| 13 | Edit from outside | group | Same mirror + supersede path, labelled as WhatsApp-sent |
| 14 | Reaction from Chatwoot / from outside | group + DM | Agent-attributed chip / `You` chip |
| 15 | Revocation from Chatwoot / from outside | group + DM | Whole edit family soft-deleted, idempotent |
| 16 | Delivery acks | real DMs | 1 726 `delivered` + 4 614 `read` applied monotonically |
| 17 | Location / vCard / poll / image via API | group | Location attachment with coordinates + maps URL; vCard text + `.vcf`; poll metadata + readable body; image downloaded |
| 18 | Initial dense history | whole account | Converged in 4 passes / 17m43s: 844 chats, 31 690 messages, silent + backdated + resolved |
| 19 | Gap-fill semantics | real DM | Recovered message returns **unread**, conversation stays `open`, `agent_last_seen_at` untouched, provenance `waha_import_kind=gap_fill`, no `imported` flag |
| 20 | Reconnection | session stop → start | `STOPPED → STARTING → WORKING` recorded; reconnect gap-fill computed and **queued** behind the running import (single-flight held) |
| 21 | Webhook config drift | session restarted outside Chatwoot | `sync_webhook_config` restored the webhook on the next status poll |
| 22 | Session isolation | webhook endpoint | Foreign `session` → HTTP 422; unknown token → HTTP 404 |
| 23 | Live media transient failure | real payload, unreachable host | 2 retries then terminal; **no message and no mapping persisted** while retryable |
| 24 | Live media terminal failure | real payload, 404 media | Message persisted with `media_download_failed` and the visible "Media unavailable" fallback |
| 25 | Send failure | invalid destination | WAHA 500 after 75 s → `TransientError`, attempt released to `pending`, retry scheduled, ambiguity reconciled as `unresolved` |

Idempotency: GOWS supports `GET /{session}/new-message-id`, so every outgoing
part carries a client-defined id that is reused across retries. The
"accepted but response lost" window is therefore reconcilable on this engine
(`delivery_ambiguous` reports `recovered` or `unresolved`).

## Defects found and fixed

1. **Self-chat identity was never anchored.** `Waha::ContactResolver` drops the
   session's own number as an identity (correct for a `fromMe` message in
   someone else's chat), then fell back to the raw JID — so the
   "message yourself" chat was keyed `558892627433@s.whatsapp.net` while every
   anchoring lookup normalizes to `@c.us`. Edits, reactions, revocations and
   acks on that chat exhausted their retries and were dropped
   (`event_retries_exhausted event=message.edited reason=missing_anchor`).
   Fixed by normalizing that fallback and by rekeying a ContactInbox stored
   under a non-canonical phone JID once the phone identity is known.
2. **A session blip permanently failed history chats.** While the session was
   restarting, GOWS answered every history page with
   `HTTP 422 "Session status is not as expected. Try again later or restart the
   session"`. The client classified all 4xx as permanent, so
   `Waha::ImportChatWorkerJob` failed 11 chats on the first try without using
   its 5-attempt budget; one failed row then fails the whole import
   (`reason: chat_failed`), and the reconciler only revisits *active* imports,
   so recovery required a manual retry. That specific 422 is now transient.

## GOWS limitations and observed behaviour

- **Pending-event retries are bounded at ~9 s** (3 tries, 3 s apart). During
  the initial import 227 events exhausted them because their base message had
  not been imported yet: 150 `message.ack.group`, 46 `message.ack`,
  27 `message.revoked`, 3 `message.reaction`, 1 `message.edited`. Acks are
  cosmetic, but a dropped revocation leaves a message visible in Chatwoot that
  no longer exists on WhatsApp. The budget is tuned for the live race
  (~1 s of contact/conversation resolution), not for a multi-hour backfill.
- **Group acks are per participant.** `message.ack.group` fires once per member;
  with the base message missing it is the single largest source of exhausted
  retries above.
- **Historical media is frequently unrecoverable.** 1 834 history items came
  back from WAHA with no downloadable media (`outcome=terminal
  reason=not_attached`) — media older than the device's retention is simply not
  there. Each produces the visible "Media unavailable" fallback rather than a
  silent gap. A further 756 downloads failed transiently and stayed queued
  behind the circuit breaker (301 `media_backlog_paused`).
- **`templateMessage` has no converter.** 460 real messages fell through to the
  visible fallback with `reason=templateMessage` — by far the most common
  unsupported node on this account.
- **Status broadcasts are ignored by policy**, observably: 474
  `event_ignored reason=status_broadcast_chat`.
- **GOWS also emits a legacy `message` event** alongside `message.any`
  (134 occurrences, ignored as `unsupported_event`); subscribing to both would
  double-process every message.
- **`GET /{session}/groups` returns raw whatsmeow shapes** (`JID`, `Name`,
  `Participants`), not the WEBJS `id._serialized` envelope.
- **A session restarted outside Chatwoot loses its webhook configuration.**
  Chatwoot repairs it on the next inbox status poll; until then no events
  arrive.
- **Live and historical copies of one message carry different timestamps** —
  the live path uses insertion time, history the WhatsApp timestamp (5 s apart
  in the observed case). Dedup is by stanza id, so this never duplicates.
- **Poll votes were not exercised**: the CORE tier allows a single session, so
  no second participant could vote. `poll.vote` handling stays covered by
  fixtures and specs only.

## Enterprise overlay

- No Enterprise file references WAHA: `enterprise/` contains no WAHA model,
  service, job, controller, policy or view, and no `prepend_mod_with` hook is
  declared by the WAHA code.
- `Channel::Waha` includes `Channelable`, whose Enterprise prepend writes an
  `Enterprise::AuditLog` row on `after_update`. Every high-frequency WAHA
  channel write (`update_import_state!`, `update_session_status`,
  `log_status_event`) uses `update_column(s)`, which skips callbacks, so an
  Enterprise install gets no audit-log amplification from an import.
- `Enterprise::Message` adds a `call` association and extends `push_event_data`
  for `content_type == 'voice_call'`. `Waha::CallEventService` deliberately
  writes `activity` messages and never creates a `Call`, so the two do not
  collide.
- `Enterprise::Concerns::Contact` reacts only to `email` and `last_activity_at`
  changes; the identity fields this ticket touched (`ContactInbox#source_id`,
  `Contact#phone_number`) are outside it.
- No plan-specific behaviour was introduced in the OSS tree and no public
  contract changed shape.

## Test and lint status

- `bundle exec rspec` over the WAHA services, jobs, models, controllers and
  webhook jobs: **466 examples, 0 failures**.
- `bundle exec rubocop` on every changed file: clean.
- No frontend files changed.

## Environment hazard found during the run

`config/database.yml` resolves every environment's database from the same
`POSTGRES_DATABASE` variable, and the local `.env` sets it to `chatwoot_dev`.
`bundle exec rspec` therefore ran against — and truncated — the development
database, destroying the homologation dataset mid-run. A `.env.test` pinning
`POSTGRES_DATABASE=chatwoot_test` now prevents this; Dotenv never overrides a
real environment variable, so CI keeps whatever it exports.
