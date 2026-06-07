# Kanban UI/UX Technical Audit

Etapa: B20.1
Escopo: auditoria tecnica para reestruturacao de UI/UX do Kanban.
Restricoes desta etapa: sem alteracao funcional, sem migration, sem mudanca de comportamento, sem push.

## 1. Arquitetura atual de rotas e paginas

### Frontend

Arquivos principais:

- `app/javascript/dashboard/routes/dashboard/kanban/routes.js`
- `app/javascript/dashboard/routes/dashboard/kanban/KanbanView.vue`
- `app/javascript/dashboard/routes/dashboard/kanban/KanbanConversationCard.vue`
- `app/javascript/dashboard/routes/dashboard/kanban/KanbanOpportunityPicker.vue`
- `app/javascript/dashboard/routes/dashboard/kanban/KanbanOpportunityDetailsModal.vue`
- `app/javascript/dashboard/components-next/sidebar/Sidebar.vue`
- `app/javascript/dashboard/routes/dashboard/dashboard.routes.js`

Rotas atuais:

- `accounts/:accountId/kanban`, nome `kanban_boards`, componente `KanbanView`.
- `accounts/:accountId/kanban/:boardId`, nome `kanban_board_show`, componente `KanbanView`.
- Ambas usam `meta.permissions = ['administrator', 'agent']`.

O componente principal da pagina e `KanbanView.vue`. Ele concentra:

- listagem e criacao de boards;
- selecao/navegacao entre boards;
- edicao/exclusao de board;
- criacao/edicao/exclusao/reordenacao de stages;
- paginacao por stage;
- drag and drop de cards;
- criacao manual de card;
- modal de detalhes do card;
- listener realtime do Kanban.

Como o board ativo e escolhido hoje:

- `activeBoardId = Number(route.params.boardId) || null`.
- `fetchBoards()` chama `KanbanBoardsAPI.get()`.
- Se nao ha `boardId` na rota, seleciona `boards[0]` e faz `router.replace({ name: 'kanban_board_show', boardId })`.
- Se ha `boardId`, chama `showBoard(boardId)`.
- `watch(activeBoardId)` recarrega o board quando o parametro muda.

Como ocorre navegacao entre boards hoje:

- A propria pagina tem um `aside` interno com a lista de boards.
- `selectBoard(boardId)` faz `router.push({ name: 'kanban_board_show', params: { boardId } })`.
- Ao remover o board ativo, a UI escolhe `boards[0]` ou volta para `kanban_boards`.

Pontos para separar as novas telas:

- Visao geral dos funis: criar rota dedicada para `accounts/:accountId/kanban`, sem redirecionar automaticamente para o primeiro board. A listagem de boards deve continuar usando `GET /kanban_boards`, mas com payload suficiente para cards/resumo se necessario.
- Pagina individual de cada funil: manter ou evoluir `accounts/:accountId/kanban/:boardId` para componente dedicado, por exemplo `KanbanBoardPage.vue`, mantendo `GET /kanban_boards/:id` como contrato de board + stages + primeira pagina de cards.
- Pagina de configuracoes do funil: adicionar rota posterior, por exemplo `accounts/:accountId/kanban/:boardId/settings`, reaproveitando `PATCH /kanban_boards/:id` e novos contratos de visibilidade/escopo quando existirem.
- O `KanbanView.vue` atual deve ser dividido em componentes menores antes do redesign para reduzir risco: navegacao, header/config, stage column, card, filtros, create/edit modal.

Sidebar principal:

- `Sidebar.vue` ja define um item raiz `Kanban` com `to: accountScopedRoute('kanban_boards')` e `activeOn: ['kanban_boards', 'kanban_board_show']`.
- Hoje nao ha submenu de boards no menu principal; a lista vive dentro da pagina Kanban.
- Local adequado para submenu: transformar o item `Kanban` em grupo com filhos:
  - `Visao geral` -> `kanban_boards`;
  - lista de funis visiveis -> `kanban_board_show`.
- Para isso, a sidebar precisara buscar boards autorizados ou consumir um store/cache compartilhado. O endpoint de listagem devera retornar somente boards visiveis ao usuario.

## 2. Backend de boards

Arquivos principais:

- `app/models/kanban_board.rb`
- `app/controllers/api/v1/accounts/kanban_boards_controller.rb`
- `app/controllers/api/v1/accounts/kanban_boards/stages_controller.rb`
- `app/controllers/api/v1/accounts/kanban_boards/cards_controller.rb`
- `app/controllers/api/v1/accounts/kanban_boards/stages/cards_controller.rb`
- `app/views/api/v1/accounts/kanban_boards/*.jbuilder`
- `app/policies/kanban_board_policy.rb`
- `app/policies/kanban_card_policy.rb`
- `config/routes.rb`

`KanbanBoard` campos atuais:

- `id`
- `account_id`
- `name`
- `description`
- `position`
- `active`
- `auto_create_cards_from_conversations`
- `use_opportunity_card_reads`
- `created_at`
- `updated_at`

Associacoes:

- `belongs_to :account`
- `has_many :kanban_stages, dependent: :destroy_async`
- `has_many :conversation_kanban_states, dependent: :destroy_async`
- `has_many :kanban_cards, dependent: nil`

Validacoes:

- `account_id` presente;
- `name` presente e unico por `account_id` apenas quando `active = true`;
- `position` presente e inteiro.

Soft delete:

- Boards usam `active=false`.
- `destroy` do controller faz `@kanban_board.update!(active: false)` e retorna `204`.
- Listagem/show sempre buscam boards ativos.

Endpoints atuais:

- `GET /api/v1/accounts/:account_id/kanban_boards`
- `POST /api/v1/accounts/:account_id/kanban_boards`
- `GET /api/v1/accounts/:account_id/kanban_boards/:id`
- `PATCH /api/v1/accounts/:account_id/kanban_boards/:id`
- `DELETE /api/v1/accounts/:account_id/kanban_boards/:id`
- `POST /kanban_boards/:kanban_board_id/stages`
- `PATCH /kanban_boards/:kanban_board_id/stages/:id`
- `PATCH /kanban_boards/:kanban_board_id/stages/:id/reorder`
- `DELETE /kanban_boards/:kanban_board_id/stages/:id`
- `GET /kanban_boards/:kanban_board_id/stages/:stage_id/cards`
- `POST /kanban_boards/:kanban_board_id/cards/manual`
- `GET /kanban_boards/:kanban_board_id/cards/by_id/:id`
- `PATCH /kanban_boards/:kanban_board_id/cards/by_id/:id`
- `DELETE /kanban_boards/:kanban_board_id/cards/by_id/:id`
- `PATCH /kanban_boards/:kanban_board_id/cards/by_id/:id/reorder`
- `GET/PUT /kanban_boards/:kanban_board_id/cards/by_id/:id/labels`
- `GET/POST /conversations/:conversation_id/kanban_cards`

Payload atual da listagem de boards:

```json
[
  {
    "id": 1,
    "account_id": 1,
    "name": "Sales",
    "description": null,
    "position": 0,
    "active": true,
    "auto_create_cards_from_conversations": false,
    "created_at": 1710000000,
    "updated_at": 1710000000
  }
]
```

Payload atual do show:

- dados do board;
- `stages[]`;
- em cada stage:
  - dados da stage;
  - `cards_count`;
  - `cards[]` usando `_compact_card.json.jbuilder`;
  - `pagination.limit`;
  - `pagination.has_more`;
  - `pagination.next_cursor`.

Boards inativos:

- nao aparecem na listagem;
- nao podem ser carregados por show;
- nao sao elegiveis para criacao automatica;
- cards em boards inativos sao bloqueados por policy/query.

## 3. Permissoes atuais

Representacao nativa:

- Usuario: `User`.
- Relacao usuario-conta e papel: `AccountUser`, com `role: agent` ou `administrator`.
- Agente e admin sao usuarios associados a conta via `account_users`.
- Inboxes acessiveis ao agente: `User#inboxes` por `InboxMember`.
- Times acessiveis: `User#teams` por `TeamMember`.
- Admins sao tratados por `account_user.administrator?`.

Policies reutilizaveis:

- `KanbanBoardPolicy`: `index?`/`show?` permitem admin ou agent; mutacoes so admin.
- `KanbanCardPolicy`: valida escopo do card, board, stage, contact, inbox e usa `ConversationPolicy` para cards com conversa; cards manuais exigem admin ou acesso ao inbox.
- `ConversationPolicy`: admin, agent bot ou agente com acesso ao inbox/time da conversa.
- `InboxPolicy`: usar para contratos de inbox quando a UI listar inboxes autorizadas.

Como validar que um agente pertence a conta:

- `Current.account.account_users.exists?(user_id: user_id)`.
- Para obter papel, `Current.account.account_users.find_by(user_id: user_id)`.
- Para garantir que e agente/admin ativo no dominio atual, usar `account_user.agent?` ou `account_user.administrator?`.

Tratamento recomendado para admins:

- Admins devem enxergar e operar todos os boards, independentemente de restricoes por agente e inbox.
- A visibilidade por agente deve ser aplicada apenas para `account_user.agent?`.
- Mutacoes administrativas de configuracao continuam restritas a admin, salvo decisao futura explicita.

Locais onde a futura restricao de visibilidade por agente precisa entrar:

- `KanbanBoardsController#index`: retornar apenas boards visiveis.
- `KanbanBoardsController#show`: impedir acesso direto a board nao visivel.
- `StagesController`: update/create/delete/reorder devem continuar admin; se agentes ganharem mutacoes, validar board visivel.
- `Stages::CardsController#index`: garantir board/stage visiveis antes da query.
- `CardsController#show/update/destroy/reorder`: validar board visivel alem de `KanbanCardPolicy`.
- `CardsController#create_manual`: validar board visivel e inbox permitido pelo board.
- `CreateFromConversationService`: validar board visivel para criacao pela sidebar.
- `AutoCreateFromConversationService`: aplicar elegibilidade por escopo de inbox, nao por usuario interativo.
- `Conversation::KanbanCardsController#index`: filtrar cards por boards visiveis.
- `KanbanConversationCards.vue`: listagem/criacao na sidebar da conversa deve consumir apenas boards visiveis.
- `KanbanView.vue` e `Sidebar.vue`: submenu e pagina devem refetch quando permissoes mudarem.
- Realtime: eventos continuam account-wide hoje; listeners devem refetch autorizado e remover itens que sumirem.

Schema recomendado para visibilidade por agentes, sem implementar:

```ruby
create_table :kanban_board_members do |t|
  t.references :account, null: false, foreign_key: true
  t.references :kanban_board, null: false, foreign_key: true
  t.references :user, null: false, foreign_key: true
  t.timestamps
end

add_index :kanban_board_members,
          [:kanban_board_id, :user_id],
          unique: true
add_index :kanban_board_members,
          [:account_id, :user_id, :kanban_board_id],
          name: 'index_kanban_board_members_on_account_user_board'
```

Contrato recomendado:

- Board sem membros explicitos pode significar "visivel para todos os agentes" ou "somente admins". A decisao de produto deve ser fixada antes da migration.
- Recomendacao tecnica: adicionar campo de modo no board para evitar semantica ambigua:
  - `visibility_mode`: `all_agents` ou `selected_agents`;
  - tabela `kanban_board_members` usada quando `selected_agents`.
- Admin ignora `visibility_mode`.

## 4. Inboxes

Arquivos principais:

- `app/models/inbox.rb`
- `app/models/inbox_member.rb`
- `app/controllers/api/v1/accounts/inboxes_controller.rb`
- `app/views/api/v1/accounts/inboxes/index.json.jbuilder`
- `app/javascript/dashboard/api/inboxes.js`
- `app/javascript/dashboard/store/modules/inboxes.js`
- `shared/components/ui/MultiselectDropdown.vue`
- `dashboard/components-next/combobox/TagMultiSelectComboBox.vue`
- `dashboard/components-next/combobox/ComboBox.vue`

Model e associacoes nativas:

- `Inbox belongs_to :account`.
- `Inbox belongs_to :channel, polymorphic: true`.
- `Inbox has_many :inbox_members`.
- `Inbox has_many :members, through: :inbox_members, source: :user`.
- `Inbox has_many :conversations`.
- `User has_many :inbox_members` e `has_many :inboxes, through: :inbox_members`.

Endpoint/API frontend existente:

- `GET /api/v1/accounts/:account_id/inboxes`.
- `Inboxes` API client em `app/javascript/dashboard/api/inboxes.js`.
- Store `inboxes/get` ja e carregada na sidebar principal.
- Controller usa `policy_scope(Current.account.inboxes)` e inclui channel, portal, working hours e avatar.

Componentes reutilizaveis para selecao multipla:

- `shared/components/ui/MultiselectDropdown.vue` e `MultiselectDropdownItems.vue`: ja usado em acoes da conversa.
- `dashboard/components-next/combobox/TagMultiSelectComboBox.vue`: componente novo para multi-select com tags.
- `dashboard/components-next/combobox/ComboBox.vue`: single-select reutilizavel.
- Para configuracao de board, `TagMultiSelectComboBox` tende a encaixar melhor no padrao components-next.

Locais onde o futuro escopo por inbox precisa entrar:

- `KanbanBoardsController#index/show`: expor `allowed_inbox_ids`/resumo somente para admin/configuracao ou aplicar filtro de visibilidade.
- `VisibleStageCardsQuery`: filtrar cards por `kanban_cards.inbox_id` e/ou `conversations.inbox_id`.
- `CreateManualCardService`: validar que `inbox_id` esta permitido no board.
- `CreateFromConversationService`: validar que a conversa pertence a inbox permitida no board.
- `AutoCreateFromConversationService`: criar card apenas em boards cujo escopo inclui o inbox da conversa.
- `Conversation::KanbanCardsController#index/create`: nao listar/criar card em board cujo escopo exclui o inbox da conversa.
- `KanbanOpportunityPicker.vue`: ao escolher contato/inbox, filtrar inboxes permitidas pelo board.
- `KanbanConversationCards.vue`: ao abrir form da conversa, listar boards compativeis com o inbox da conversa.
- Realtime: eventos de card cujo inbox saiu do escopo devem causar refetch e remocao local.

Schema recomendado para inboxes permitidas, sem implementar:

```ruby
create_table :kanban_board_inboxes do |t|
  t.references :account, null: false, foreign_key: true
  t.references :kanban_board, null: false, foreign_key: true
  t.references :inbox, null: false, foreign_key: true
  t.timestamps
end

add_index :kanban_board_inboxes,
          [:kanban_board_id, :inbox_id],
          unique: true
add_index :kanban_board_inboxes,
          [:account_id, :inbox_id, :kanban_board_id],
          name: 'index_kanban_board_inboxes_on_account_inbox_board'
```

Contrato recomendado:

- Usar `inbox_scope_mode`: `all_inboxes` ou `selected_inboxes`.
- Quando `selected_inboxes`, exigir ao menos um inbox ativo.
- Admin pode configurar todos; agente ve boards pela intersecao entre board visivel, inbox permitido no board e inboxes do agente.

## 5. Cards e payload atual

Arquivos principais:

- `app/models/kanban_card.rb`
- `app/services/kanban_cards/visible_stage_cards_query.rb`
- `app/views/api/v1/accounts/kanban_boards/_compact_card.json.jbuilder`
- `app/views/api/v1/accounts/kanban_boards/_card.json.jbuilder`
- `app/views/api/v1/accounts/conversations/kanban_cards/_kanban_card.json.jbuilder`
- `KanbanConversationCard.vue`
- `KanbanConversationCards.vue`

Payload atual do card no board (`_compact_card`):

- `id`
- `kanban_stage_id`
- `position`
- `origin`
- `subject`
- `active`
- `contact` completo via `api/v1/models/contact`
- `inbox` slim via `api/v1/models/inbox_slim`
- `conversation_id` com `conversation.display_id`, nao id interno
- `moved_by_id: nil`
- `moved_at: nil`

Payload atual do card detalhado (`_card`):

- campos acima;
- `account_id`, `kanban_board_id`, timestamps;
- `starts_at` e `due_at` apenas quando `stable_card=true`;
- `conversation` completo quando existe.

Payload atual na sidebar da conversa:

- `id`
- `origin`
- `subject` com fallback textual;
- `due_at` e `labels[]` quando `include_metadata=true`;
- `kanban_board: { id, name }`
- `kanban_stage: { id, name, color }`
- `conversation_id` com display id.

Dados para novo layout compacto:

- `subject`: ja existe em `kanban_cards.subject`.
- `contact id/name/avatar`: ja existe via `contact` parcial; precisa reduzir para payload slim.
- `inbox id/name/tipo`: ja existe via `inbox_slim`; tipo vem de `channel_type`/`inbox_type` conforme partial.
- `assignee id/name/avatar`: hoje so vem indiretamente em `conversation.meta.assignee` no payload detalhado; nao vem no `_compact_card`.
- `priority/urgencia`: vem de `conversation.priority`; nao vem no `_compact_card`.
- `due_at`: existe no model, mas nao vem no `_compact_card`; vem no `_card` quando `stable_card`.
- `tempo na etapa`: nao existe campo confiavel em `kanban_cards`.
- `conversation_id`: hoje e display id, nao id interno. O frontend usa esse valor para navegar.

Risco de N+1:

- `VisibleStageCardsQuery#payload_cards` inclui `:conversation`, `contact: { avatar_attachment: :blob }`, `inbox: [:channel, { avatar_attachment: :blob }]`.
- O `_compact_card` atual nao serializa assignee; se passar a serializar `conversation.assignee`, precisa incluir `conversation: { assignee: { avatar_attachment: :blob } }`.
- Se serializar labels no board compacto, precisa incluir `:labels`.
- Se serializar inbox channel tipo/nome a partir de channel, `inbox: [:channel]` ja esta coberto.

Preloads recomendados:

```ruby
includes(
  contact: { avatar_attachment: :blob },
  inbox: [:channel, { avatar_attachment: :blob }],
  conversation: [
    { assignee: { avatar_attachment: :blob } }
  ]
)
```

Se labels entrarem no card compacto:

```ruby
includes(:labels, contact: ..., inbox: ..., conversation: ...)
```

Payload compacto final recomendado, sem implementar:

```json
{
  "id": 123,
  "board_id": 10,
  "stage_id": 20,
  "position": 1,
  "origin": "conversation",
  "subject": "Upgrade plan",
  "conversation": {
    "id": 456,
    "display_id": 789,
    "priority": "urgent"
  },
  "contact": {
    "id": 55,
    "name": "Jane Doe",
    "avatar_url": "https://..."
  },
  "inbox": {
    "id": 7,
    "name": "Sales",
    "channel_type": "Channel::Email"
  },
  "assignee": {
    "id": 9,
    "name": "Agent Name",
    "avatar_url": "https://..."
  },
  "due_at": "2026-06-10T12:00:00Z",
  "stage_entered_at": "2026-06-07T10:00:00Z",
  "time_in_stage_seconds": 7200
}
```

## 6. Tempo na etapa

Estado atual:

- `kanban_cards` nao tem `stage_entered_at`.
- `conversation_kanban_states` tem `moved_at`/`moved_by_id`, mas os novos fluxos com `KanbanCard` nao criam nem atualizam `ConversationKanbanState`.
- `_compact_card` ainda retorna `moved_at: nil` e `moved_by_id: nil`.
- `updated_at` nao e adequado para tempo na etapa porque muda em edicao de assunto, datas, labels, normalizacao de posicao, delete logico e reorder interno.

Fluxos que movem ou posicionam card:

- Drag and drop no board: `KanbanView.vue#onCardDragChange` -> `PATCH cards/by_id/:id/reorder`.
- Reorder interno na mesma stage: mesmo endpoint e `KanbanCard#reorder_to_position!`.
- Move entre stages: mesmo endpoint ou `CardsController#update` quando recebe `kanban_stage_id`.
- Criacao manual: `CreateManualCardService`, sempre entra na posicao 1 da stage.
- Criacao pela sidebar da conversa: `CreateFromConversationService`, sempre entra na posicao 1 da stage.
- Criacao automatica: `AutoCreateFromConversationService`, usa primeira stage ativa.
- Edicao pela sidebar: `KanbanConversationCards.vue#submitEdit` -> `updateCardDetailsById` com `kanban_stage_id`; backend usa `CardsController#update`.
- `SyncConversationStateService`: sincroniza legado de `ConversationKanbanState` para `KanbanCard`, mas novos fluxos nao dependem dele.
- Backfill/parity tasks: `lib/tasks/kanban_cards.rake`.

Estrategia recomendada para `stage_entered_at`, sem implementar:

- Adicionar `kanban_cards.stage_entered_at`, `datetime`, nullable inicialmente.
- Setar no create para `Time.current`.
- Atualizar somente quando `kanban_stage_id` mudar.
- Nao atualizar em reorder dentro da mesma stage.
- Nao atualizar em edicao de subject, due date, labels ou normalizacao de posicoes.
- Centralizar no model/service para cobrir `reorder_to_position!`, `CardsController#update`, services de criacao e sync.
- Backfill:
  - Para cards com `conversation_kanban_states.moved_at` correspondente, usar `moved_at`.
  - Para demais cards ativos, usar `kanban_cards.created_at`.
  - Para cards inativos, usar `created_at` ou deixar nullable conforme necessidade historica.
- Depois do backfill, avaliar `null: false`.

## 7. Filtros futuros

Endpoint paginado atual por stage:

- `GET /api/v1/accounts/:account_id/kanban_boards/:board_id/stages/:stage_id/cards`
- Controller: `Api::V1::Accounts::KanbanBoards::Stages::CardsController#index`.
- Query: `KanbanCards::VisibleStageCardsQuery`.

Cursor atual:

- `pagination.next_cursor = { after_id: last_card_id }`.
- O anchor e resolvido dentro do conjunto visivel.
- Ordenacao: `position ASC, created_at ASC, id ASC`.
- Se o anchor nao existe mais no conjunto visivel, retorna `409 { error: 'refresh_required' }`.

`cards_count`/`has_more`:

- No `show`, cada stage recebe `cards_count = total_count`.
- Endpoint paginado retorna `pagination.total_count`, `has_more`, `next_cursor`, `limit`.

Queries atuais:

- Base: `KanbanCard.active.left_outer_joins(:conversation)`.
- Filtros fixos: `account_id`, `kanban_board_id`, `kanban_stage_id`.
- Visibilidade:
  - admin: card manual ou card de conversa valida;
  - agent bot: apenas card de conversa valida;
  - agente: manual em inbox acessivel ou conversa acessivel por inbox/time.

Como adicionar filtros server-side:

- `inbox_ids[]`: aplicar em `kanban_cards.inbox_id`.
- `assignee_ids[]`: join em `conversations` e aplicar `conversations.assignee_id`.
- Manter filtros dentro de `visible_cards` para que `total_count`, cursor e pagina usem o mesmo conjunto.
- Filtros devem ser parte dos params do endpoint e do cache mental do frontend; ao mudar filtro, resetar paginas e refetch do board/stage.

Joins necessarios:

- Inbox: nao precisa join; `kanban_cards.inbox_id`.
- Assignee: ja existe `left_outer_joins(:conversation)`; para filtrar assignee, usar `conversation_table[:assignee_id]`.
- Se for permitir `unassigned`, tratar `assignee_id IS NULL`.

Indices a avaliar posteriormente, sem criar agora:

- `kanban_cards(kanban_board_id, kanban_stage_id, inbox_id, position, created_at, id) WHERE active = true`
- `kanban_cards(kanban_board_id, kanban_stage_id, due_at, position, created_at, id) WHERE active = true` se ordenar/filtrar vencimento.
- `conversations(account_id, assignee_id, inbox_id)` se assignee virar filtro frequente.
- Indices das futuras tabelas `kanban_board_members` e `kanban_board_inboxes` descritos acima.

## 8. Stages

Arquivos principais:

- `app/models/kanban_stage.rb`
- `app/controllers/api/v1/accounts/kanban_boards/stages_controller.rb`
- `app/views/api/v1/accounts/kanban_boards/_stage.json.jbuilder`
- `KanbanView.vue`

Model atual:

- Campos: `account_id`, `kanban_board_id`, `name`, `position`, `active`, `color`, timestamps.
- `color` e `string`, default `"blue"`, `null: false`.
- Soft delete por `active=false`.
- Validacao de nome unico por board quando active.
- Validacao de consistencia entre conta da stage e board.

Cores atuais no frontend:

- Lista fixa em `KanbanView.vue#stageColorOptions`:
  - `blue`
  - `teal`
  - `amber`
  - `ruby`
  - `iris`
  - `violet`
- Fallback visual na sidebar da conversa usa `bg-n-slate-9`.

Componente reutilizavel para ampliar paleta:

- Hoje as swatches estao inline em `KanbanView.vue`.
- Recomenda-se extrair para um componente pequeno, por exemplo `KanbanStageColorPicker.vue`, ou reaproveitar um combobox/dropdown components-next se a paleta virar configuravel.

Local para definir cinza como padrao de novos stages:

- Backend definitivo: default de `kanban_stages.color` em migration futura e fallback/model default.
- Frontend: `defaultStageColor` em `KanbanView.vue`.
- Recomendacao: alinhar ambos para `slate`/`gray` no mesmo bloco de implementacao e manter fallback visual para cores antigas.

## 9. Drag and drop

Biblioteca atual:

- `vuedraggable`, wrapper Vue para SortableJS.

Componentes envolvidos:

- `KanbanView.vue` usa `Draggable` para stages e para cards.
- `KanbanConversationCard.vue` renderiza cada card.

Eventos atuais:

- Stages: `@end="onStageDragEnd"`.
- Cards: `@start`, `@change`, `@end`.
- Persistencia do card ocorre em `@change`, chamando `PATCH cards/by_id/:id/reorder`.

Suporte atual:

- `ghost-class="opacity-60"`.
- `chosen-class="opacity-90"`.
- `:animation="180"`.
- Cards usam `fallback-on-body`, `force-fallback`, `empty-insert-threshold`, `swap-threshold`.
- Nao ha clone customizado, preview inclinado, cursor customizado, nem ocultacao explicita do card de origem.

Abordagem recomendada, sem implementar:

- Ocultar card da origem durante drag:
  - usar estado `draggingCardId` e classe no card original;
  - testar com fallback do Sortable para evitar sumico do clone.
- Preview inclinado junto ao cursor:
  - usar `force-fallback` com `fallback-class` e CSS Tailwind/utility global existente se suportado;
  - ou slot/clone customizado se a versao do vuedraggable permitir.
- Restauracao em erro:
  - manter snapshot imutavel de `selectedBoard.stages` no `@start`;
  - em erro, restaurar snapshot e refetch das stages afetadas.
- Stage vazia:
  - manter `min-h` e placeholder sem `pointer-events`, como hoje;
  - validar `empty-insert-threshold` em mobile.

## 10. Edicao e exclusao de cards no board

Estado atual:

- Edicao detalhada no board: `KanbanOpportunityDetailsModal.vue`, aberto por `selectedOpportunityCardId`.
- Exclusao: `woot-delete-modal` em `KanbanView.vue`, usando `DELETE cards/by_id/:id`.
- Card atual `KanbanConversationCard.vue` abre detalhes ao clicar no artigo.
- Botao remover ja usa `@click.stop`.
- Endpoints reutilizaveis:
  - `GET cards/by_id/:id`
  - `PATCH cards/by_id/:id`
  - `DELETE cards/by_id/:id`
  - `PUT cards/by_id/:id/labels`

Comportamento necessario futuro:

- Clique no corpo abrir conversa:
  - hoje `openConversation(card)` existe em `KanbanView.vue`, mas nao e usado no card do board; o card emite `openDetails`.
  - precisa passar evento separado para corpo vs botoes.
- Hover exibir editar/excluir:
  - `KanbanConversationCard.vue` deve emitir `openDetails` em botao de editar e `removeCard` em botao excluir.
  - Ambos com `stopPropagation`.
- Card sem conversa nao navegar:
  - `openConversation` hoje nao guarda `card.conversationId`; se chamado com card manual sem conversa, montaria URL invalida.
  - Adicionar guard quando implementar clique de navegacao.

## 11. Tela de conversa

Arquivos principais:

- `app/javascript/dashboard/components/widgets/conversation/ConversationBox.vue`
- `app/javascript/dashboard/components/widgets/conversation/ConversationHeader.vue`
- `app/javascript/dashboard/components/buttons/ResolveAction.vue`
- `app/javascript/dashboard/routes/dashboard/conversation/ContactPanel.vue`
- `app/javascript/dashboard/routes/dashboard/conversation/Kanban/KanbanConversationCards.vue`
- `app/javascript/dashboard/components/widgets/conversation/MessagesView.vue`
- `app/javascript/dashboard/components-next/message/bubbles/Text/FormattedContent.vue`
- `app/javascript/dashboard/components-next/message/bubbles/Email/Index.vue`

Header da conversa:

- Componente: `ConversationHeader.vue`.
- Nome do contato: `currentContact.name`, renderizado em `span`.
- Avatar e nome usam `currentContact` do store.
- Botao atual para abrir detalhes do perfil: a abertura do painel lateral e controlada pelo `ConversationSidebar`/`SidepanelSwitch` e `uiSettings.is_contact_sidebar_open`; o header em si nao abre o painel ao clicar no nome.
- Painel lateral de perfil: `ContactPanel.vue`.
- Botao Resolver: `ResolveAction.vue`, normalmente montado via acoes de conversa/header.

Pontos adequados para mudancas:

- Clicar no nome abrir detalhes:
  - adicionar handler em `ConversationHeader.vue` no bloco do nome;
  - atualizar `uiSettings.is_contact_sidebar_open = true`;
  - manter acessibilidade via `button`.
- Adicionar lupa ao lado de Resolver:
  - melhor ponto e na area de acoes do header, proximo a `ResolveAction`/`MoreActions`, ou dentro de `ConversationHeader.vue` se o evento abrir busca local.
- Abrir busca em painel lateral:
  - a busca B18 atual e inline em `ConversationBox.vue`;
  - para painel lateral, extrair estado/acoes para composable ou componente dedicado e renderizar no slot/sidebar.

Busca B18 atual:

- Barra inline em `ConversationBox.vue`, `data-testid="conversation-search-bar"`.
- Estado:
  - `isConversationSearchOpen`
  - `conversationSearchQuery`
  - `conversationSearchResults`
  - `conversationSearchMeta`
  - `activeConversationSearchResultIndex`
  - loading/errors/abort controllers
- Atalho: Ctrl/Cmd+F.
- Endpoint de busca:
  - `GET /conversations/:conversation_id/messages/search`
  - controller: `MessagesController#search`
  - finder: `ConversationMessageSearchFinder`
  - params: `q`, `limit`, `before_id`
  - meta: `total_count`, `limit`, `has_more`, `next_before_id`
- Endpoint de janela:
  - `GET /conversations/:conversation_id/messages/window`
  - finder: `MessageWindowFinder`
  - params: `around`, `before_limit`, `after_limit`
- Vuex merge:
  - action `mergeConversationMessageWindow` em `store/modules/conversations/actions.js`.
- Highlight:
  - `conversationSearchQuery` e `activeConversationSearchResultId` passam para `MessagesView`.
  - `FormattedContent.vue` e `Email/Index.vue` usam `highlightSearchTerm` com classe `conversation-search-highlight`.
- Scroll:
  - `document.getElementById("message#{id}")?.scrollIntoView(...)`.

Reaproveitamento recomendado:

- Reusar finders/endpoints sem alterar contrato.
- Extrair UI/estado de busca de `ConversationBox.vue` para componente/composable antes de mover para painel.
- Manter `MessagesView` recebendo `conversationSearchQuery` e `activeConversationSearchResultId`.

## 12. Larguras da interface

Locais atuais:

- Lista de conversas: `ChatList.vue`, wrapper `conversations-list-wrap` usa `w-[340px] 2xl:w-[412px]`; em layout expandido usa `basis-full`.
- Lista interna: `ConversationList.vue`, classe `conversations-list`.
- Painel de detalhes/perfil da conversa:
  - `ConversationSidebar.vue` e `ContactPanel.vue` compoem o painel;
  - `EditContact.vue` usa drawer `w-[30rem] max-w-full`;
  - layouts contacts-next usam sidebars `w-[85%] sm:w-[50%]`.
- Sidebar principal: `Sidebar.vue` tem largura redimensionavel via `sidebarWidth`.

Riscos responsivos:

- Aumentar simultaneamente lista, conversa e painel lateral pode quebrar viewports medios.
- `ConversationHeader.vue` ja tem altura responsiva `h-24 xl:h-12`; mais botoes podem causar wrap.
- Busca em painel lateral competira por largura com acordeoes e Kanban sidebar.

Sugestao de alteracao isolada posterior:

- Criar um bloco especifico para larguras da conversa, alterando apenas `ChatList.vue`/sidebar de detalhes.
- Testar mobile, layout condensado e layout expandido.
- Nao misturar com permissao/escopo Kanban.

## 13. Realtime

Eventos atuais:

- `kanban.board.updated`
- `kanban.stage.created`
- `kanban.stage.updated`
- `kanban.stage.deleted`
- `kanban.stage.reordered`
- `kanban.card.created`
- `kanban.card.updated`
- `kanban.card.deleted`
- `kanban.card.reordered`

Arquivos:

- `lib/events/types.rb`
- `app/listeners/action_cable_listener.rb`
- `app/javascript/dashboard/helper/actionCable.js`
- `app/javascript/dashboard/routes/dashboard/kanban/KanbanView.vue`
- `app/javascript/dashboard/routes/dashboard/conversation/Kanban/KanbanConversationCards.vue`

Payloads atuais:

- Board: `account_id`, `board_id`.
- Stage: `account_id`, `board_id`, `stage_id`.
- Card create/update/delete: `account_id`, `board_id`, `stage_id`, `card_id`, `conversation_id`.
- Card reorder: `account_id`, `board_id`, `card_id`, `conversation_id`, `source_stage_id`, `target_stage_id`.
- Payload e intencionalmente compacto; frontend refaz fetch autorizado.

Listeners frontend:

- `actionCable.js` traduz eventos para `BUS_EVENTS.KANBAN_REALTIME_EVENT`.
- `KanbanView.vue`:
  - ignora evento de outro board;
  - board/stage events -> `refreshSelectedBoard`;
  - create/delete -> refetch primeira pagina da stage;
  - reorder -> refetch stage origem/destino;
  - update -> busca card por id e patch local ou refetch stage.
- `KanbanConversationCards.vue`:
  - escuta apenas eventos de card;
  - se `conversation_id` ausente, considera relevante;
  - se houver `conversation_id`, compara com conversa atual;
  - refetch da lista da sidebar.

Impactos futuros:

- Alteracao de permissao por agente:
  - evento account-wide pode chegar para agente que perdeu acesso; listener deve chamar endpoint autorizado e remover board/card local quando 403/404.
  - sidebar principal precisa refetch de boards.
- Alteracao de escopo por inbox:
  - boards/cards podem sumir da lista do agente ou da conversa; refetch autorizado obrigatorio.
- Criacao/renomeacao/exclusao de boards:
  - hoje so existe `kanban.board.updated`; nao ha evento de created/deleted.
  - Para submenu lateral, criar eventos `kanban.board.created` e `kanban.board.deleted` ou usar evento generico de lista invalidada.
- Atualizacao do submenu lateral:
  - precisa store/composable de boards com listener realtime.
  - Refetch deve ser autorizado, nunca confiar no payload realtime para inserir item visivel.

Pontos que exigirao refetch autorizado:

- Qualquer mudanca em `kanban_board_members`.
- Qualquer mudanca em `kanban_board_inboxes`.
- Board create/update/delete.
- Stage create/update/delete/reorder.
- Card create/update/delete/reorder.

## 14. Testes

Specs backend relevantes:

- `spec/models/kanban_board_spec.rb`
- `spec/models/kanban_stage_spec.rb`
- `spec/models/kanban_card_spec.rb`
- `spec/models/kanban_card_concurrency_spec.rb`
- `spec/models/conversation_kanban_state_spec.rb`
- `spec/policies/kanban_card_policy_spec.rb`
- `spec/controllers/api/v1/accounts/kanban_boards_controller_spec.rb`
- `spec/controllers/api/v1/accounts/kanban_boards/stages_controller_spec.rb`
- `spec/controllers/api/v1/accounts/kanban_boards/cards_controller_spec.rb`
- `spec/controllers/api/v1/accounts/kanban_boards/stages/cards_controller_spec.rb`
- `spec/controllers/api/v1/accounts/conversations/kanban_cards_controller_spec.rb`
- `spec/services/kanban_cards/visible_stage_cards_query_spec.rb`
- `spec/services/kanban_cards/create_manual_card_service_spec.rb`
- `spec/services/kanban_cards/create_from_conversation_service_spec.rb`
- `spec/services/kanban_cards/auto_create_from_conversation_service_spec.rb`
- `spec/services/kanban_cards/sync_conversation_state_service_spec.rb`
- `spec/jobs/kanban_cards/auto_create_from_conversation_job_spec.rb`
- `spec/listeners/action_cable_listener_spec.rb`
- `spec/listeners/kanban_card_listener_spec.rb`
- `spec/finders/conversation_message_search_finder_spec.rb`
- `spec/finders/message_window_finder_spec.rb`

Specs frontend relevantes:

- `app/javascript/dashboard/routes/dashboard/kanban/specs/KanbanView.spec.js`
- `app/javascript/dashboard/routes/dashboard/kanban/specs/KanbanConversationCard.spec.js`
- `app/javascript/dashboard/routes/dashboard/kanban/specs/KanbanOpportunityPicker.spec.js`
- `app/javascript/dashboard/routes/dashboard/kanban/specs/KanbanOpportunityDetailsModal.spec.js`
- `app/javascript/dashboard/routes/dashboard/conversation/Kanban/specs/KanbanConversationCards.spec.js`
- `app/javascript/dashboard/routes/dashboard/conversation/specs/ContactPanel.spec.js`
- `app/javascript/dashboard/components/widgets/conversation/specs/ConversationBox.spec.js`
- `app/javascript/dashboard/components/widgets/conversation/specs/MessagesView.spec.js`
- `app/javascript/dashboard/helper/specs/actionCable.spec.js`
- Message highlight specs em `components-next/message/bubbles`.

Lacunas de cobertura:

- Board visibility por agente ainda nao existe.
- Board inbox scope ainda nao existe.
- Sidebar principal com submenu de boards ainda nao existe.
- `stage_entered_at` e tempo na etapa nao existem.
- Filtros server-side por inbox/assignee nao existem.
- Payload compacto com assignee, priority, due_at e time in stage nao existe.
- Drag preview/clone/ocultacao de origem nao cobertos.
- Clique no corpo do card para abrir conversa ainda nao e comportamento atual.
- Eventos realtime de board created/deleted/list invalidation nao existem.
- Busca B18 ainda esta acoplada em `ConversationBox.vue`, o que dificulta mover para painel.

## Decisoes recomendadas

1. Separar arquitetura de paginas antes do redesign visual:
   - overview;
   - board show;
   - board settings.
2. Criar store/composable frontend para boards visiveis e reutilizar na sidebar e paginas.
3. Usar `visibility_mode` + `kanban_board_members` para visibilidade por agentes.
4. Usar `inbox_scope_mode` + `kanban_board_inboxes` para escopo por inbox.
5. Admin deve ignorar restricoes de agente/inbox para visibilidade e configuracao.
6. Centralizar autorizacao de board em policy/scope antes de aplicar em controllers/services.
7. Manter realtime compacto e fazer refetch autorizado.
8. Adicionar `stage_entered_at` em bloco isolado com backfill proprio.
9. Evoluir `_compact_card` para payload slim, evitando serializar conversa completa no board.
10. Extrair busca de conversa para componente/composable antes de mover para painel lateral.

## Riscos principais

- Ambiguidade de boards sem membros/inboxes se nao houver campo de modo.
- Vazamento de board no submenu se a sidebar consumir listagem sem autorizacao final no backend.
- Criacao automatica gerar cards em boards fora do escopo do inbox.
- Realtime account-wide exibindo itens obsoletos ate o refetch; precisa tratar 403/404.
- `updated_at` produzir tempo na etapa incorreto.
- Novo payload compacto causar N+1 se assignee/labels forem adicionados sem preload.
- Aumentos de largura da conversa podem quebrar layout condensado/mobile.
- `KanbanView.vue` esta grande e concentra muitos fluxos; redesign direto aumenta risco de regressao.

## Divisao sugerida dos proximos blocos

1. Rotas e layout base:
   - criar paginas overview/show/settings sem mudar contratos;
   - mover lista de boards para store/composable;
   - adicionar submenu na sidebar usando listagem atual.
2. Schema de visibilidade por agentes:
   - migration de `visibility_mode` e `kanban_board_members`;
   - policy scopes;
   - listagem/show/services/sidebar.
3. Schema de escopo por inbox:
   - migration de `inbox_scope_mode` e `kanban_board_inboxes`;
   - filtros nos services de criacao e queries;
   - UI de configuracao com multi-select.
4. Payload compacto e redesign de cards:
   - ajustar serializer/preloads;
   - novo componente compacto;
   - hover editar/excluir e clique para conversa.
5. `stage_entered_at`:
   - migration;
   - backfill;
   - atualizacao nos fluxos de movimento/criacao;
   - payload de tempo na etapa.
6. Filtros server-side:
   - params por stage;
   - filtros inbox/assignee;
   - UI de filtros;
   - avaliar indices com dados reais.
7. Drag and drop refinado:
   - snapshot/restore;
   - preview/ghost;
   - stage vazia;
   - testes frontend.
8. Conversa:
   - extrair busca B18;
   - abrir detalhes pelo nome;
   - lupa ao lado de Resolver;
   - busca em painel lateral.
9. Realtime:
   - eventos de board created/deleted ou invalidacao;
   - refetch autorizado na sidebar;
   - specs para remocao por perda de acesso.
