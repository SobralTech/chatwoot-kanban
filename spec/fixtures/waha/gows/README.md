# GOWS message fixtures

Real WAHA `message` webhook payloads captured from the GOWS engine, anonymized:
phone numbers replaced with reserved test ranges, names and addresses replaced,
message/stanza IDs and thumbnails shortened. Everything else — field names,
casing and nesting — is left exactly as GOWS emits it, because that shape is
the contract the converters are written against:

- message-type keys under `_data.Message` are lower camel case
  (`locationMessage`, `contactsArrayMessage`, `pollCreationMessage`,
  `listMessage`, `eventMessage`);
- fields whose proto name ends in an acronym keep it (`URL`, `JPEGThumbnail`,
  `remoteJID`, `stanzaID`, `mentionedJID`);
- `_data.Info` uses the Go struct's own PascalCase (`Chat`, `PushName`);
- WAHA additionally normalizes some of this into engine-agnostic top-level
  fields (`location`, `vCards`, `replyTo`), which the fixtures keep so the
  best-effort path for other engines is exercised too.

`poll_vote.json` is the GOWS `poll.vote` webhook envelope. Its `payload.poll`
uses the corrected poll-creation key emitted by the GOWS adapter and
`payload.vote.selectedOptions` is the decrypted selection. Poll updates are
separate from `message.any`, so both fixtures are part of the contract.

`pix_payment.json`, `facebook_ad_reply.json`, `album_header.json` and the
`album_item_*.json` files were not captured from a live session — no GOWS
session carrying these three message types was available. They are
reconstructed field-for-field from whatsmeow's own generated proto source
(`go.mau.fi/whatsmeow/proto/waE2E`, `WAWebProtobufsE2E.pb.go`), which fixes
the exact JSON field names GOWS emits regardless of live capture: `title`,
`body`, `thumbnailURL`, `mediaURL`, `sourceID`, `sourceURL` under
`contextInfo.externalAdReply` (`ContextInfo_ExternalAdReplyInfo`);
`expectedImageCount`/`expectedVideoCount` under `albumMessage`; and
`messageContextInfo.messageAssociation` (`associationType`,
`parentMessageKey.ID`) linking an album's individual photos/videos back to
its header, none of which the current converters read yet. The PIX button
payload's inner JSON (`payment_settings`, `pix_static_code`, `total_amount`)
matches the shape the more mature reference WAHA→Chatwoot app already parses
in production. The doubled `interactiveMessage.interactiveMessage` nesting in
`pix_payment.json` mirrors a GOWS oneof-serialization quirk that same
reference app works around — proto reflection says a oneof should flatten,
but real GOWS output does not. These four fixtures should be replaced with
genuine anonymized captures once a live GOWS session emits these types,
per SPEC.md's release gate.
