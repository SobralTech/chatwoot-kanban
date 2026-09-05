# GOWS message fixtures

Real WAHA `message` webhook payloads captured from the GOWS engine, anonymized:
phone numbers replaced with reserved test ranges, names and addresses replaced,
message/stanza IDs and thumbnails shortened. Everything else — field names,
casing and nesting — is left exactly as GOWS emits it, because that shape is
the contract the converters are written against:

- message-type keys under `_data.Message` are lower camel case
  (`locationMessage`, `contactsArrayMessage`, `extendedTextMessage`);
- fields whose proto name ends in an acronym keep it (`URL`, `JPEGThumbnail`,
  `remoteJID`, `stanzaID`, `mentionedJID`);
- `_data.Info` uses the Go struct's own PascalCase (`Chat`, `PushName`);
- WAHA additionally normalizes some of this into engine-agnostic top-level
  fields (`location`, `vCards`, `replyTo`), which the fixtures keep so the
  best-effort path for other engines is exercised too.
