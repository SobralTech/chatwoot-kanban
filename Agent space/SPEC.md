# Spec: Nova Inbox WAHA para Chatwoot

## 1. Visão Geral

Implementar um novo canal nativo `Channel::Waha` no Chatwoot que se integra diretamente à API do WAHA (WhatsApp HTTP API), substituindo o app WAHA atual. A nova inbox é para um **número novo** — sem migração da inbox existente.

### Funcionalidades principais
- Receber e enviar mensagens (DMs e grupos)
- **Fix do reply em mensagens antigas** (bug crítico do setup atual)
- Edição de mensagens enviadas (com lock de UI em mensagens >15 min)
- Deleção bidirecional sincronizada (Chatwoot ↔ WhatsApp)
- Reações exibidas em tempo real
- Widget de status de conexão com QR code inline
- Importação de histórico com progresso
- Reconexão automática configurável
- Read receipts automáticos configuráveis

### Fora de escopo
- Status messages do WhatsApp (stories) — ignorar completamente
- Channels/newsletters (`@newsletter`) — ignorar
- Templates de mensagem (não é BSP)
- Migração da inbox antiga (número diferente)

---

## 2. Arquitetura

### Novo canal: `Channel::Waha`

Canal separado do `Channel::Whatsapp` existente. Tabela própria, controller próprio, serviços próprios. Sem acoplamento com WhatsApp Cloud / 360dialog.

```
app/
  models/channel/waha.rb
  controllers/webhooks/waha_controller.rb
  jobs/webhooks/waha_events_job.rb
  services/waha/
    incoming_message_service.rb
    outgoing_message_service.rb
    session_service.rb
    import_service.rb
    contact_resolver.rb
db/migrate/
  create_channel_waha.rb
```

### Tabela `channel_waha`

| Coluna | Tipo | Notas |
|--------|------|-------|
| `id` | bigint PK | |
| `account_id` | integer FK | |
| `phone_number` | string | número do WhatsApp |
| `waha_url` | string | URL do servidor WAHA (ex: `https://waha.exemplo.com`) |
| `api_key` | string | API key do WAHA (Bearer token) |
| `session_name` | string | nome da sessão WAHA (ex: `7433_numero`) |
| `webhook_token` | string | UUID gerado na criação, usado na URL do webhook |
| `groups_enabled` | boolean | default: false |
| `auto_reconnect` | boolean | default: true |
| `auto_read_receipts` | boolean | default: true |
| `session_status` | string | cache local: WORKING/FAILED/STOPPED/SCAN_QR_CODE/STARTING |
| `status_history` | jsonb | array dos últimos 20 eventos de status `[{status, timestamp}]` |
| `created_at` / `updated_at` | datetime | |

---

## 3. Configuração da Inbox

### Campos na UI de criação/edição da inbox

- **URL do servidor WAHA** — ex: `https://waha.empresa.com`
- **API Key** — token Bearer para autenticação nas chamadas à API WAHA
- **Nome da sessão** — session name configurado no WAHA (ex: `7433_numero`)
- **Número de telefone** — para exibição/identificação
- **Aceitar mensagens de grupos** (toggle, default: off)
- **Reconexão automática** (toggle, default: on)
- **Read receipts automáticos** (toggle, default: on)

### Webhook gerado automaticamente

Na criação da inbox, o Chatwoot gera um `webhook_token` UUID e exibe a URL que deve ser configurada no WAHA:

```
https://chatwoot.empresa.com/webhooks/waha/{webhook_token}
```

O WAHA deve enviar todos os eventos para essa URL. O token na URL funciona como autenticação (equivalente ao verify token do WhatsApp).

### Eventos WAHA a configurar no webhook

```
message.any, message.ack, message.revoked, message.edited,
message.reaction, session.status
```

> Usamos `message.any` (não `message`) como único evento de mensagem recebida/enviada.
> Ele é o superset e cobre ambas as direções, evitando processar a mesma mensagem duas vezes.

---

## 4. Webhook Endpoint

### Rota

```ruby
# config/routes.rb
post '/webhooks/waha/:token', to: 'webhooks/waha#process_payload'
```

### Controller

```ruby
# app/controllers/webhooks/waha_controller.rb
class Webhooks::WahaController < ApplicationController
  skip_before_action :verify_authenticity_token

  def process_payload
    channel = Channel::Waha.find_by(webhook_token: params[:token])
    return head :not_found unless channel

    WahaEventsJob.perform_later(channel.id, permitted_params.to_h)
    head :ok
  end
end
```

### Eventos processados

Assinamos **apenas `message.any`** no WAHA (superset de todos os eventos de mensagem),
para que cada mensagem seja processada exatamente uma vez, independentemente da direção.
O `chatId` de qualquer direção vem de `_data.Info.Chat` (para `fromMe`, `from` é o **nosso**
próprio número, não o contato).

| Evento WAHA | Ação no Chatwoot |
|-------------|------------------|
| `message.any` + `fromMe: false` | Mensagem recebida (de contato) → mensagem `incoming` |
| `message.any` + `fromMe: true` + `source: 'app'`/`'web'` | Mensagem enviada pelo **celular/WhatsApp Web** → espelhar como `outgoing` (sem agente) |
| `message.any` + `fromMe: true` + `source: 'api'` | Enviada pelo próprio Chatwoot → só confirmar entrega (atualizar status), não espelhar |
| `message.revoked` | Deletar mensagem no Chatwoot (se não tiver flag `syncing`) |
| `message.edited` | Atualizar conteúdo da mensagem (se não tiver flag `syncing`) |
| `message.reaction` | Registrar/exibir reação na mensagem |
| `session.status` | Atualizar `session_status` e `status_history` no channel |
| `message.ack` | Atualizar ACK da mensagem (enviada → entregue → lida) |

### Filtros de tipo de chat

- Mensagens de `@newsletter` — ignorar
- Mensagens de `status@broadcast` — ignorar
- Mensagens de `@g.us` (grupos) — processar somente se `groups_enabled: true`
- Mensagens de `@c.us` / `@lid` (DMs) — sempre processar

---

## 5. Resolução de Contatos

### DMs: problema @lid vs @c.us

O WAHA usa dois formatos de JID para o mesmo contato. O mesmo número pode chegar como `558894397552@c.us` (JID real) ou `74324878868496@lid` (JID ofuscado). Sem tratamento, o Chatwoot cria contatos duplicados.

**Estratégia: normalizar para @c.us antes de qualquer lookup/criação**

```
Se chatId termina em @lid:
  GET /api/{session}/contacts/{lid} → obter o @c.us real
  Usar o @c.us para buscar/criar contato
Senão:
  Usar o chatId direto
```

O atributo `identifier` do contato no Chatwoot armazenará o `@c.us` (ex: `558894397552@c.us`).

O campo `additional_attributes` do contato guarda o `@lid` como alias para referência futura.

### Grupos: contact = o grupo

Quando uma mensagem de grupo chega (`chatId` termina em `@g.us`):
1. Buscar/criar um **contato representando o grupo** com `identifier = chatId` (ex: `558892627433-1608816654@g.us`)
2. Nome do contato = nome do grupo (buscar via `GET /api/{session}/groups/{chatId}`)
3. Campo `additional_attributes.is_group: true`, `additional_attributes.participant` guarda o JID de quem enviou a mensagem
4. Mensagens dentro da conversa do grupo têm `sender_name` = pushName do participante

---

## 6. Modelo de Mensagens e source_id

### Formato do source_id

Armazenar o **ID completo do WAHA** no `source_id` de cada mensagem:

```
{fromMe}_{chatId}_{stanzaId}
```

Exemplos:
- DM recebida: `false_558892627433@c.us_3EB040610E912211B90A74`
- DM enviada: `true_558892627433@c.us_3EB0D0C990CC21762A3FB4`
- Grupo enviada: `true_558892627433-1608816654@g.us_3EB0D0C990CC21762A3FB4_558892627433@c.us`

**O stanzaId é a última parte após o último `_`.**

### Lookup por replyTo (fix do bug crítico)

Quando um webhook chega com `payload.replyTo.id = "3EB040610E912211B90A74"` (stanzaId curto):

```ruby
# Buscar por sufixo no source_id
message = conversation.messages
  .where("source_id LIKE ?", "%_#{reply_to_id}")
  .or(where(source_id: reply_to_id))  # fallback se já estiver no formato curto
  .first
```

### Envio de reply com replyTo

Quando o agente responde a uma mensagem no Chatwoot, o serviço de envio deve incluir `reply_to` com o **source_id completo** da mensagem citada:

```ruby
payload[:reply_to] = quoted_message.source_id
# Ex: "false_558892627433@c.us_3EB040610E912211B90A74"
```

---

## 7. Operações de Mensagem

### 7.1 Envio de mensagens

| Tipo | Endpoint WAHA |
|------|---------------|
| Texto | `POST /api/sendText` |
| Imagem com legenda | `POST /api/sendImage` |
| Documento/arquivo | `POST /api/sendFile` |
| Áudio (voz) | `POST /api/sendVoice` |

Todos os endpoints recebem `session`, `chatId`, e opcionalmente `reply_to` (source_id completo da mensagem citada).

### 7.2 Edição de mensagens

**Apenas mensagens enviadas pelo agente (`fromMe: true`) e com menos de 15 minutos.**

- Na UI: botão "Editar" aparece somente para mensagens `fromMe` com `created_at > Time.now - 15.minutes`
- Ao confirmar a edição: setar `syncing: true` em `additional_attributes`, chamar `PUT /api/{session}/chats/{chatId}/messages/{messageId}`
- `chatId` extraído do source_id (segundo segmento separado por `_`)
- `messageId` = source_id completo
- Após resposta da API: atualizar conteúdo da mensagem no Chatwoot, remover flag `syncing`
- Em caso de erro da API: reverter UI, mostrar toast de erro, remover flag `syncing`

### 7.3 Deleção bidirecional

#### Chatwoot → WhatsApp

Trigger: `after_destroy` callback no model `Message`, filtrado por inbox tipo WAHA.

```ruby
# Apenas mensagens fromMe podem ser apagadas no WhatsApp
if message.outgoing? && message.inbox.channel.is_a?(Channel::Waha)
  message.update_column(:additional_attributes,
    message.additional_attributes.merge('syncing' => true))
  WahaDeleteMessageJob.perform_later(message.id)
end
```

O job chama `DELETE /api/{session}/chats/{chatId}/messages/{messageId}`.

#### WhatsApp → Chatwoot

Webhook `message.revoked` recebido:
1. Extrair `revokedMessageId` (ou `before.id`)
2. Buscar mensagem no Chatwoot por source_id (sufixo)
3. Se a mensagem tiver `additional_attributes.syncing = true` → **ignorar** (loop prevention)
4. Caso contrário: marcar mensagem como deletada no Chatwoot

### 7.4 Loop Prevention (flag `syncing`)

Antes de qualquer ação de deleção ou edição iniciada pelo Chatwoot:
1. Setar `additional_attributes['syncing'] = true` na mensagem
2. Disparar operação na API WAHA
3. No webhook handler: checar `additional_attributes['syncing']` antes de processar `message.revoked` ou `message.edited`
4. Se `syncing: true` → limpar o flag e retornar sem processar
5. Se a chamada WAHA falhar: limpar o flag e reportar erro

### 7.5 Read Receipts

Se `auto_read_receipts: true` na inbox:
- Quando um agente abre uma conversa com mensagens não lidas, disparar chamada ao endpoint de ACK do WAHA para marcar como lido
- Endpoint: `POST /api/{session}/chats/{chatId}/messages/{messageId}/ack` (ou endpoint equivalente da API)

---

## 8. Reações

- Webhook `message.reaction` → buscar mensagem por `source_id` (sufixo) → salvar/atualizar reações no `additional_attributes['reactions']` da mensagem
- Frontend exibe emojis de reação abaixo da mensagem
- Não há envio de reações pelo agente no MVP

---

## 9. Widget de Status de Conexão

Localização: aba de configurações da inbox, seção dedicada "Status da Conexão".

### Estados exibidos (mapeados do WAHA)

| Status WAHA | Display no Chatwoot |
|-------------|---------------------|
| `WORKING` | 🟢 Conectado |
| `FAILED` | 🔴 Falha na conexão |
| `STOPPED` | ⚫ Parado |
| `SCAN_QR_CODE` | 🟡 Aguardando QR code |
| `STARTING` | 🟡 Iniciando... |

### Ações disponíveis

- **Reconectar** — chama `POST /api/sessions/{session}/restart` (visível quando status ≠ WORKING)
- **Logout** — chama `POST /api/sessions/{session}/logout` (confirmar antes)
- **QR Code inline** — quando status = `SCAN_QR_CODE`, buscar o QR via polling `GET /api/sessions/{session}` e exibir imagem inline na página de settings
- **Histórico de status** — tabela com os últimos 20 eventos: status + timestamp (dados do `channel.status_history`)

### Atualização do status

1. Webhook `session.status` chega → atualizar `channel.session_status` + append em `channel.status_history`
2. Admin também pode forçar refresh via botão que chama `GET /api/sessions/{session}` no backend

---

## 10. Reconexão Automática

Se `auto_reconnect: true` na inbox:

1. Webhook `session.status` com status = `FAILED` → disparar `WahaReconnectJob` após 30s
2. O job chama `POST /api/sessions/{session}/restart`
3. Se status voltar para `WORKING` → sucesso, notificar admin via in-app notification
4. Se status continuar `FAILED` após 3 tentativas (com backoff exponencial: 30s, 2min, 5min) → notificar admin e parar tentativas

---

## 11. Notificações para Admin

### Quando a sessão cai definitivamente (sem reconexão bem-sucedida)

- **In-app notification** (sino do Chatwoot): "Inbox [nome] desconectada — verifique a sessão WAHA"
- **Banner na inbox** (visível para agentes): aviso vermelho persistente até a reconexão

---

## 12. Importação de Histórico

### UI

Na aba de configurações da inbox WAHA: seção "Importar histórico".

Campos:
- **Data de início** — date picker (mensagens a partir desta data)
- **Importar grupos** — checkbox (só aparece se grupos estiverem habilitados na inbox)
- Botão **Iniciar importação**

### Job em background

```ruby
WahaImportJob.perform_later(channel.id, since_date: params[:since_date], include_groups: params[:include_groups])
```

**Fluxo do job:**

1. Listar todos os chats via `GET /api/{session}/chats`
2. Filtrar: excluir `@newsletter`, excluir `status@broadcast`, excluir `@g.us` se `include_groups: false`
3. Para cada chat, paginar mensagens com `GET /api/{session}/chats/{chatId}/messages?filter.timestamp.gte={unix_timestamp}&downloadMedia=true&limit=100`
4. Para cada mensagem: verificar se já existe (source_id match por sufixo), criar contato/conversa/mensagem se não existir
5. Download e armazenamento de mídia via ActiveStorage
6. Atualizar contador de progresso no Redis: `waha_import:{job_id}:progress`

### Progresso na UI

- Frontend polling a cada 3s em `GET /api/v1/inboxes/:id/waha/import_status`
- Retorna `{ total_chats, processed_chats, imported_messages, status: 'running'|'completed'|'failed' }`
- Barra de progresso atualiza em tempo real

### Deduplicação

Match por sufixo de source_id (stanzaId). Se a mensagem já existe: pular. Garante idempotência — importação pode ser re-executada sem duplicatas.

---

## 13. Detalhes de Implementação: Extração do chatId do source_id

Para operações que precisam do `chatId` e `stanzaId` separados (edit, delete, ACK):

```ruby
def parse_source_id(source_id)
  # Formato DM:    "true_558892627433@c.us_3EB0D0C990CC21762A3FB4"
  # Formato grupo: "true_558892627433-1608816654@g.us_3EB0D0C990CC21762A3FB4_558892627433@c.us"
  parts = source_id.split('_')
  from_me = parts[0] == 'true'
  # chatId é tudo entre o primeiro e o último segmento identificável
  # Detecção: grupos têm @g.us, DMs têm @c.us ou @lid
  chat_id_index = parts.index { |p| p.include?('@') }
  stanza_id = parts.last.include?('@') ? nil : parts.last
  chat_id = parts[1...-1].join('_') # tudo exceto from_me e stanza_id
  { from_me:, chat_id:, stanza_id: }
end
```

---

## 14. Resumo das Decisões Técnicas

| Decisão | Escolha |
|---------|---------|
| Arquitetura | `Channel::Waha` separado |
| Autenticação webhook | Token UUID na URL |
| source_id format | ID completo WAHA; lookup por sufixo |
| Grupos | Uma conversa por grupo; contact = grupo |
| @lid dedup | Resolver para @c.us via API WAHA |
| Deleção bidirecional | after_destroy callback no model |
| Loop prevention | Flag `syncing` em `additional_attributes` |
| Edição de mensagens | Só fromMe, UI desabilitada >15min |
| Read receipts | Auto ao abrir conversa (configurável) |
| Status messages | Ignorado completamente |
| Channels/newsletter | Ignorado |
| Mídia na importação | Download completo para ActiveStorage |
| Progresso importação | Redis counter + polling frontend |
| Reconexão | Auto (configurável) + notificação após 3 falhas |
| Admin alerts | In-app notification + banner na inbox |
| QR code | Inline nas configurações da inbox |
