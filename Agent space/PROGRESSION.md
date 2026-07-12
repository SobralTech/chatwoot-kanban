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

## Decisões Técnicas Registradas

- `contact_inbox.source_id` = chatId do WAHA (ex: `558892627433@c.us`)
- `message.source_id` = ID completo WAHA (`{fromMe}_{chatId}_{stanzaId}`)
- Reply lookup via `LIKE "%_#{stanzaId}"` (fix do bug crítico)
- @lid dedup: resolver para @c.us via API WAHA antes de criar contato
- Grupos: uma conversa por grupo, contact = o grupo
- Webhook autenticado por token UUID na URL (não por signature)
- Canal usa `Base::SendOnChannelService` padrão do Chatwoot
