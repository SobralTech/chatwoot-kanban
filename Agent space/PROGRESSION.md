# Channel::Waha — Progresso

> Este arquivo tem no máximo 300 linhas. Resumo do que foi feito, o que falta e as etapas.

---

## Visão Geral do Projeto

Integração nativa Chatwoot ↔ WAHA (WhatsApp HTTP API) como canal próprio `Channel::Waha`,
substituindo o app WAHA existente. Fix crítico de reply, sync bidirecional, status, reconexão e importação.

Spec completa: `Agent space/SPEC.md`

---

## Fases do Projeto

| Fase | Descrição | Status |
|------|-----------|--------|
| **1** | Core: receive/send mensagens, criação de inbox, fix de reply | ✅ Implementado |
| **2** | Sync bidirecional: edição, deleção, reações, ACK/read receipts | ⬜ Pendente |
| **3** | Status widget, reconexão automática, notificações admin | ⬜ Pendente |
| **4** | Importação de histórico com progresso em tempo real | ⬜ Pendente |

---

## Fase 1 — Implementado

### Backend

| Arquivo | Status |
|---------|--------|
| `db/migrate/20260712100000_create_channel_waha.rb` | ✅ |
| `app/models/channel/waha.rb` | ✅ |
| `app/controllers/webhooks/waha_controller.rb` | ✅ |
| `app/jobs/webhooks/waha_events_job.rb` | ✅ |
| `app/services/waha/http_client.rb` | ✅ |
| `app/services/waha/contact_resolver.rb` | ✅ |
| `app/services/waha/incoming_message_service.rb` | ✅ |
| `app/services/waha/send_on_waha_service.rb` | ✅ |
| `config/routes.rb` — rota webhook | ✅ |
| `app/jobs/send_reply_job.rb` — +Channel::Waha | ✅ |
| `app/controllers/api/v1/accounts/inboxes_controller.rb` — +waha | ✅ |
| `app/models/inbox.rb` — predicado waha? | ✅ |

### Frontend

| Arquivo | Status |
|---------|--------|
| `channels/Waha.vue` — wizard de criação | ✅ |
| `ChannelFactory.vue` — +waha | ✅ |
| `ChannelList.vue` — +waha na lista | ✅ |
| `helper/inbox.js` — INBOX_TYPES.WAHA | ✅ |
| `i18n/locale/en/inboxMgmt.json` — strings WAHA | ✅ |

---

## Fase 2 — Pendente

- `after_destroy` callback em `Message` para deleção bidirecional
- `app/jobs/waha/delete_message_job.rb`
- `app/services/waha/delete_message_service.rb`
- Handler de `message.revoked` no job (com flag `syncing`)
- Handler de `message.edited` no job (com flag `syncing`)
- Handler de `message.reaction` → salvar em `additional_attributes['reactions']`
- Handler de `message.ack` → atualizar status da mensagem
- Read receipts automáticos ao abrir conversa

---

## Fase 3 — Pendente

- Novo endpoint: `GET /api/v1/accounts/:id/inboxes/:id/waha/session_status`
- Widget de status na aba de configurações da inbox
- QR Code inline quando `session_status = SCAN_QR_CODE`
- Tabela de status_history
- `app/jobs/waha/reconnect_job.rb` com backoff exponencial
- In-app notification quando sessão cai definitivamente

---

## Fase 4 — Pendente

- `app/jobs/waha/import_job.rb`
- Endpoint `GET /api/v1/accounts/:id/inboxes/:id/waha/import_status`
- UI: seção de importação com date picker + barra de progresso
- Progresso via Redis

---

## Como Testar (Fase 1)

```bash
# Migrations
bundle exec rails db:migrate

# Criar inbox via API
POST /api/v1/accounts/1/inboxes
{
  "name": "WAHA Test",
  "channel": {
    "type": "waha",
    "phone_number": "+5511999999999",
    "waha_url": "https://waha.empresa.com",
    "api_key": "token123",
    "session_name": "session1"
  }
}

# Simular webhook
curl -X POST http://localhost:3000/webhooks/waha/{webhook_token} \
  -H "Content-Type: application/json" \
  -d '{"event":"message","session":"session1","payload":{...}}'

# Linting
bundle exec rubocop app/models/channel/waha.rb app/services/waha/
```

---

## Fix Sessão/QR Code (2026-07-12) — inbox travava em "Starting..." sem gerar QR

### O que estava errado (causa raiz confirmada por teste real na API)
1. **Auth com header errado** (bug principal): `HttpClient` mandava `Authorization: Bearer <key>`,
   mas WAHA autentica via `X-Api-Key`. Toda escrita (criar sessão) voltava **401** e o erro era
   engolido pelo `rescue`. Teste: `X-Api-Key` → 200, `Authorization: Bearer` → 401.
2. **Sessão nunca era criada**: código só chamava `POST /sessions/{name}/start`, que exige a sessão
   já existente. Faltava `POST /api/sessions`. Sem sessão, `status` vinha `nil` e o front caía no
   fallback "Starting..." pra sempre (nunca chegava em `SCAN_QR_CODE`).
3. **QR não renderizava**: backend retornava base64 cru sem prefixo, e usava `format=base64`
   (inválido; enum aceita só `image`/`raw`).
4. **Pundit 500**: faltava `waha_session_status?` em `InboxPolicy`.
5. **session_name com espaço** quebrava a URI (`bad URI`).

### O que foi feito pra funcionar
- `http_client.rb`: header de auth → `X-Api-Key: <key>`. Novo método `request(method, path, body)`
  que devolve a resposta crua (necessário pro QR binário e checar `success?`).
- `session_service.rb`: `start` agora faz `POST /api/sessions` (cria com `start: true` + webhook
  configurado) antes do `/start`. `qr_code` busca `?format=image`, lê os bytes e retorna
  **data URL pronta** (`data:image/png;base64,...`).
- `inboxes_controller.rb#waha_session_status`: auto-recuperável — se status é `nil`/`STOPPED`/`FAILED`
  (`WAHA_STARTABLE_STATUSES`), chama `service.start` e relê o status. Inbox criada antes do fix se
  recupera sozinha, sem precisar recriar.
- `inbox_policy.rb`: `+waha_session_status?` (admin).
- `channel/waha.rb`: `before_validation :sanitize_session_name` (troca chars fora de `[a-zA-Z0-9._-]` por `_`).

### Validado na API real (waha.sobraltec.com.br)
`POST /api/sessions` → 201 → status `STARTING` → `SCAN_QR_CODE` em ~5s → `GET /auth/qr?format=image`
→ PNG 292×292 válido. Fluxo ponta a ponta OK.

### Pendências / notas
- **Webhook em localhost não funciona**: WAHA externo não alcança `localhost`. Usar túnel
  (ngrok/cloudflared) apontando `FRONTEND_URL` pra URL pública, OU replay manual dos JSONs de
  exemplo via curl no endpoint local pra testar só a lógica de recebimento.
- `webhook_url` depende de `ENV['FRONTEND_URL']` ser público em produção.

Commits: `1647fa3ab` (criar sessão + QR), `afdc0288c` (X-Api-Key + self-heal).

---

## Espelhamento de mensagens enviadas pelo celular (2026-07-12)

Deveria existir desde o início: mensagens enviadas **fora do Chatwoot** (pelo celular ou
WhatsApp Web) agora aparecem na inbox como `outgoing`. Antes, só `incoming` e a confirmação
de envios via API eram tratados; qualquer coisa enviada pelo app era descartada.

### Bugs encontrados e corrigidos
1. **`message.any` com `fromMe: false` era ignorado** — mensagens recebidas nunca entravam
   se a sessão só assinasse `message.any` (caso do usuário). Corrigido no roteamento do job.
2. **`source` lido do path errado** — usava `payload._data.source` (inexistente); o correto é
   `payload.source` na raiz. Confirmação de envio via API nunca disparava.
3. **`chat_id` pegava `from`** — em mensagens `fromMe`, `from` é o **nosso** número, não o
   contato. Passou a usar `_data.Info.Chat` (fallback `to`/`from`), o JID da conversa em
   qualquer direção.

### Design final (único ponto de verdade)
- Webhook assina **só `message.any`** (superset) → cada mensagem processada uma única vez.
- Job `Webhooks::WahaEventsJob#handle_message` roteia por direção:
  - `fromMe: true` + `source: 'api'` → é do próprio Chatwoot → só `status: :delivered` (dedup).
  - resto (`fromMe: false`, ou `fromMe: true` com `source: app/web`) → `IncomingMessageService`.
- `IncomingMessageService` agora cria `incoming` **ou** `outgoing` conforme `fromMe`.
  Outgoing espelhada tem `sender = nil` (sem agente) e `source_id` preenchido, então
  `SendOnChannelService#invalid_message?` a ignora (não há loop de reenvio).

### Arquivos tocados
- `app/jobs/webhooks/waha_events_job.rb` — só `message.any`; roteamento por direção.
- `app/services/waha/incoming_message_service.rb` — `chat_id` via `_data.Info.Chat`;
  `message_type`/`sender` por direção.
- `app/services/waha/session_service.rb` — eventos do webhook = `message.any message.ack session.status`.
- `Agent space/SPEC.md` — tabela de eventos corrigida (o spec estava errado).

### Auto-sync de webhook em sessão existente (sem recriar)
WAHA só aplica config de webhook na **criação** da sessão. Para sessões antigas (ex:
`pedro_teste`) pegarem a config nova sem recriar, usamos `PUT /api/sessions/{session}`:
- `SessionService#sync_webhook_config(session_info)` compara os webhooks retornados pelo
  `GET /api/sessions/{session}` com os desejados (`WEBHOOK_EVENTS`) e só faz `PUT` se
  houver divergência — evita reiniciar a sessão a cada poll de status.
- Chamado em `InboxesController#waha_session_status`, que já é polleado ao abrir as
  configurações da inbox. Ou seja: **basta abrir a tela de status da inbox** que a config
  de webhook é corrigida automaticamente na sessão existente.
- `WEBHOOK_EVENTS = %w[message.any message.ack session.status]` centraliza a lista usada
  tanto na criação quanto no sync.

---

## Decisões Técnicas Registradas

- `contact_inbox.source_id` = chatId do WAHA (ex: `558892627433@c.us`)
- `message.source_id` = ID completo WAHA (`{fromMe}_{chatId}_{stanzaId}`)
- Reply lookup via `LIKE "%_#{stanzaId}"` (fix do bug crítico)
- @lid dedup: resolver para @c.us via API WAHA antes de criar contato
- Grupos: uma conversa por grupo, contact = o grupo
- Webhook autenticado por token UUID na URL (não por signature)
- Canal usa `Base::SendOnChannelService` padrão do Chatwoot
