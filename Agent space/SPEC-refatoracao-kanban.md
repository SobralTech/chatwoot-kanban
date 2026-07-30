# Especificação — Refatoração do Kanban

Status: aprovado para implementação (pós-entrevista)
Escopo: substitui o fluxo atual de criação/edição de funil, o modal de card, e adiciona catálogo de produtos (via API externa) + motivos de perda/ganho + campos personalizados por funil.

## 0. Contexto do estado atual (antes da mudança)

- Criação de board: dialog simples (`KanbanCreateBoardDialog.vue`), só pede nome.
- Edição de board: rota separada `/kanban/:boardId/settings` (`KanbanBoardSettings.vue`), salva cada ação imediatamente (nome/descrição via botão Salvar; estágios via API individual por criação/edição/exclusão/reorder).
- Board (`KanbanBoard`) tem: `name`, `description`, `active`, `position`, `visibility_mode` (all_agents/selected_agents) + `kanban_board_members`, `inbox_scope_mode` (all_inboxes/selected_inboxes) + `kanban_board_inboxes`, `auto_create_cards_from_conversations`.
- Stage (`KanbanStage`) tem: `name`, `color`, `position`, `active`. **Não tem `description`.**
- Card (`KanbanCard`) tem: `subject`, `description`, `due_at`, `starts_at`, `priority`, `origin` (conversation/manual), assignees, labels (via `Labelable`). **Não tem** `status` (won/lost), `value`, produtos vinculados, ou campos personalizados.
- Modal de card atual (`KanbanOpportunityDetailsModal.vue`): página única com seções (não abas): Título, Contato, Descrição, Conversa, Labels, Assignee, Prioridade, Data.
- Board view (`KanbanView.vue` + `KanbanConversationCard.vue`): colunas já têm fundo pastel por cor do estágio (`getKanbanStageBodyColorClass`) e header colorido — isso **já existe**, não precisa ser recriado. Falta: badge de status, valor por card, soma de valor por coluna.
- `pt_BR/kanban.json` já é mantido em paralelo com `en/kanban.json` neste projeto (é uma feature própria deste fork, não uma tradução comunitária padrão) — **portanto, ao contrário da regra geral do CLAUDE.md de só tocar `en.json`, esta feature deve manter `en/kanban.json` E `pt_BR/kanban.json` sincronizados**, seguindo o padrão já estabelecido no histórico de commits do projeto.

## 1. Arquitetura geral de persistência (criação e edição de funil)

- **Uma única tela com abas** substitui tanto o dialog de criação quanto a rota de settings atual. Usada tanto para "Criando: Novo Funil" quanto "Editando: <nome>".
- Ao clicar em "Novo Funil", o backend já cria um `KanbanBoard` com `active: false` (rascunho) imediatamente — recebe um `id` real.
- Cada aba/ação (criar estágio, editar nome, adicionar campo, adicionar motivo, etc.) **salva imediatamente via API**, igual ao padrão atual de `KanbanBoardSettings.vue` — não há estado "só client-side" aguardando um Salvar final.
- Botão **Salvar** (no rascunho): ativa o board (`active: true`) e volta para a listagem/board. Antes de ativar, valida que `won_stage_id` e `lost_stage_id` estão definidos (ver seção 3) — se não, bloqueia com mensagem de erro nessa aba.
- Botão **Salvar** (editando um board já ativo): não precisa reativar nada, é só uma navegação de volta (já que tudo já foi salvo incrementalmente). Pode simplesmente fechar a tela.
- Botão **Descartar**: se o board ainda é rascunho (nunca foi ativado), deleta o board rascunho e tudo relacionado. Se já está ativo (edição), apenas navega de volta sem nenhuma chamada de exclusão.
- Nenhum template de estágio padrão — funil novo nasce sem estágios (ou com o comportamento atual), sem os 4 estágios pré-preenchidos do mockup (isso era só exemplo de dados no protótipo).
- **Boards já existentes em produção** continuam ativos e funcionando normalmente, sem `won_stage_id`/`lost_stage_id` definidos — a obrigatoriedade dessas colunas só é validada quando o board é (re)salvo/ativado a partir de agora. Sem badge de status/Ganho-Perdido até que um admin configure essas colunas na tela de edição.

## 2. Estrutura de abas do funil (criação/edição)

Abas, na ordem do mockup, **exceto "Metas" e "Presets de Checklist" (fora de escopo nesta fase)**:

1. **Etapas e Dados**
2. **Campos Personalizados Globais**
3. **Configurações**
4. **Motivos de Perda e Ganho**

### 2.1 Aba "Etapas e Dados"

Reaproveita o layout do mockup (imagem 1):
- Toggle "Status Ativo" → `active`.
- Campo "Nome" → `name`.
- Campo "Descrição" → `description`.
- **"Agentes do Funil"**: busca de agente + lista de selecionados com botão remover. Substitui a UI atual de radio all/selected. **Sem** o checkbox "Supervisor" do mockup (fora de escopo).
  - Comportamento equivalente ao atual `visibility_mode`: se nenhum agente for selecionado, o board é visível pra todos (`all_agents`); se algum for selecionado, vira `selected_agents` com esses IDs.
- **Nova seção: "Inboxes"** (relocada da tela de settings atual): seleção "todas as inboxes" ou "inboxes selecionadas" — mesmo componente/lógica de hoje (`inbox_scope_mode` + `allowed_inbox_ids`), adicionada abaixo de "Agentes do Funil" nesta aba.
- Painel direito "Etapas do Funil": lista de estágios com nome, descrição, cor, drag-to-reorder, editar, excluir — igual ao comportamento atual, **adicionando um novo campo `description` ao estágio** (não existe hoje, precisa migration em `kanban_stages`).
- **Seleção de estágio de Ganho e estágio de Perdido**: nesta aba, cada estágio no painel direito ganha uma forma de ser marcado como "Estágio de Ganho" ou "Estágio de Perdido" (ex: dois selects/badges "Marcar como Ganho" / "Marcar como Perdido" por estágio, ou dois dropdowns de nível de board "Estágio de Ganho: [dropdown]" / "Estágio de Perdido: [dropdown]" populados com os estágios existentes). Ver seção 3 para a semântica completa.
- Corpo de cada card de estágio no protótipo ("Nenhuma informação adicional") é só um placeholder decorativo sem dado real por trás — **não implementar nada ali nesta fase** (é reservado para o futuro "Presets de Checklist", que está fora de escopo).

### 2.2 Aba "Campos Personalizados Globais"

- Apesar do nome "Globais", o escopo é **por funil** (cada `KanbanBoard` tem sua própria lista de definições de campo; "Globais" só significa "vale para todos os cards daquele funil", não entre funis diferentes).
- UI: lista de linhas, cada uma com:
  - **Chave (name)**: texto livre, vira o identificador técnico do campo.
  - **Tipo**: dropdown com Texto / Número / Data / Verdadeiro-Falso.
  - **Único / Lista**: segundo dropdown.
    - "Único": o card guarda um valor só daquele tipo.
    - "Lista": o card pode ter **múltiplos valores livres** do mesmo tipo (ex: várias datas, vários textos), digitados pelo agente — não é um multi-select com opções pré-cadastradas pelo admin.
  - Botão remover (x) por linha.
  - Botão "Adicionar campo" no rodapé.
- Cada linha salva/atualiza/remove via API imediatamente ao editar (debounce ou blur), consistente com a arquitetura da seção 1.

### 2.3 Aba "Configurações"

Conteúdo final, **bem mais enxuto que o mockup**:
- Toggle **"Motivo de Perda Obrigatório"** (`lost_reason_required`, novo boolean em `kanban_boards`) — único toggle específico do mockup mantido.
- **Não incluir**: "Distribuição Automática (Round-robin)" (funcionalidade nova que não existe no código hoje e fica fora de escopo) nem "Moeda Padrão" (removido — API de produtos só retorna BRL, então todo valor em tela usa formatação R$ fixa no código, sem campo configurável).
- Seção relocada: **"Criar cards automaticamente a partir de conversas"** (`auto_create_cards_from_conversations`), com o fluxo de importação de conversas existentes já implementado hoje (modal de importar, checkbox "ignorar grupos") — movida da tela antiga de settings para esta aba.
- Seção "Zona de perigo" no final: botão **Excluir Funil**, com o modal de confirmação já existente hoje.

### 2.4 Aba "Motivos de Perda e Ganho"

- Escopo **por funil** (cada `KanbanBoard` tem sua própria lista de motivos — mesma decisão dos campos personalizados).
- Duas colunas: "Motivos de Perda" e "Motivos de Ganho", com contador e empty state, igual ao mockup.
- Botão "Adicionar novo motivo" abre um popup/modal de edição com:
  - **Título** (obrigatório).
  - **Descrição** (opcional).
  - **Tipo**: radio/seleção exclusiva "Perda" ou "Ganho" (um motivo pertence a exatamente um tipo, nunca aos dois).
- Motivos existentes são editáveis/removíveis (reaproveitar o mesmo popup).
- Novo model: `KanbanLossReason` (ou nome similar) com `kanban_board_id`, `title`, `description`, `reason_type` (enum: `lost`/`won`), `account_id`, `active`, `position`.

## 3. Status do card: Aberto / Ganho / Perdido

- **O status é totalmente derivado do estágio atual do card — não é um campo independente.**
  - Se `card.kanban_stage_id == board.won_stage_id` → status exibido = **Ganho**.
  - Se `card.kanban_stage_id == board.lost_stage_id` → status exibido = **Perdido**.
  - Qualquer outro estágio → **Aberto**.
- Novo em `kanban_boards`: `won_stage_id` (FK para `kanban_stages`, nullable) e `lost_stage_id` (FK para `kanban_stages`, nullable).
- **Obrigatório definir os dois ao salvar/ativar um funil novo** (ver seção 1). Funis já existentes ficam isentos até serem editados.
- **Interação no card (imagem 7)**: clicar no badge "Aberto" abre um popover/modal para escolher Ganho ou Perdido:
  - Ao escolher, mostra um dropdown com os motivos cadastrados **daquele tipo** (Ganho → lista de motivos tipo Ganho; Perdido → lista de motivos tipo Perdido) — seleção obrigatória se: for Perdido E `lost_reason_required` estiver ativo no board. Para Ganho, o motivo é sempre opcional (não existe toggle de "motivo de ganho obrigatório").
  - Ao confirmar, o card é **movido** (via a mesma lógica de `reorder_to_position!` já existente) para `won_stage_id`/`lost_stage_id`, e o motivo escolhido é gravado no card (novo campo `kanban_card.reason_id` ou tabela de junção simples — nullable).
- **Drag-and-drop direto para o estágio de Perdido**: se `lost_reason_required` estiver ativo, o drop é interceptado — abre o popup de motivo antes de confirmar a movimentação; se o usuário cancelar, o card volta ao estágio de origem (revert visual). Se `lost_reason_required` estiver desativado, o drag-and-drop move normalmente sem popup (motivo fica nulo).
- **Drag-and-drop direto para o estágio de Ganho**: sempre permitido sem popup bloqueante (motivo de ganho nunca é obrigatório) — pode abrir o popup de forma não bloqueante para permitir selecionar motivo, ou simplesmente mover sem motivo (motivo fica nulo, editável depois pelo card).
- **Reversão**: arrastar o card de volta para qualquer estágio "normal" (nem `won_stage_id` nem `lost_stage_id`) reverte automaticamente o status para Aberto e limpa o motivo gravado.
- Badge visual: "Aberto" (neutro, com ícone de refresh/clock como no mockup), "Ganho" (verde), "Perdido" (vermelho) — clicável em todos os estados pra reabrir o seletor.

## 4. Catálogo de produtos (API externa)

### 4.1 Integração

- Fonte: API externa já existente do usuário, `https://produtos-api.sobraltec.com.br/products/search`.
- Autenticação: header `X-Agent-Token`. **O token fica em uma credencial Rails/ENV global do servidor** (ex: `Rails.application.credentials.products_api_token` ou `ENV['PRODUCTS_API_TOKEN']`) — nunca exposto ao frontend.
- **Toda chamada à API externa passa por um endpoint proxy no backend Rails** (novo controller, ex: `Api::V1::Accounts::KanbanBoards::ProductsController#search` ou um `Api::V1::Accounts::ProductsController` genérico), que repassa os query params (`text`/`sku`, `price_list`, `limit`) e injeta o header `X-Agent-Token` a partir da credencial do servidor.
- Parâmetros de busca suportados: texto livre e/ou SKU, `limit` (quantidade de resultados), `price_list` (`default` / `revenda` / `empresas_21_dias`) — **o vendedor escolhe a lista de preço na busca** (um seletor na aba Produtos do card, com "default" pré-selecionado).
- Formato de resposta conhecido (exemplo real fornecido pelo usuário):
```json
{
  "success": true,
  "pagination": { "total_results": 5, "has_more": false },
  "products": [
    {
      "sku": "29105",
      "name": "Cabo USB 2.0 para impressora AM/BM Com 3 Metros PC-USB3001 PlusCable",
      "brand": "PlusCable",
      "category_breadcrumb": "Impressão e Suprimentos > Cabos USB para Impressora",
      "attributes": { "product_type": "printer" },
      "pricing": {
        "base_price": 24.99,
        "pix_price": 23.24,
        "max_installments": 10,
        "installment_value": 2.5
      },
      "stock_quantity": 10,
      "checkout_url": "https://www.sobraltec.com.br/...",
      "image_url": "https://s3.amazonaws.com/..."
    }
  ]
}
```
  - **Identificador do produto é o `sku`** (não há campo `id` numérico).
  - `pricing.base_price` = preço parcelado/cheio; `pricing.pix_price` = preço à vista.
  - Não há cache/sincronização local do catálogo inteiro — a busca é sempre ao vivo contra a API externa (com debounce no campo de busca do front-end, ex.: 400ms).

### 4.2 Vínculo produto ↔ card

- Novo model, ex. `KanbanCardProduct`, com: `kanban_card_id`, `account_id`, `sku`, `name`, `brand` (opcional), `image_url` (opcional), `quantity`, `unit_price` (snapshot), `price_type` (enum: `pix`/`base`, registra qual preço da API foi escolhido), `price_list` (string, registra qual lista foi usada na busca), `position`/`created_at` para ordenação.
- **Snapshot no momento do vínculo**: ao adicionar um produto ao card, o backend grava uma cópia dos dados retornados pela API externa (nome, sku, preço escolhido) — não referencia o catálogo externo em tempo real depois disso. Preço do card e somas de coluna são sempre calculados localmente, sem chamadas externas.
- **Escolha de preço**: ao vincular, o vendedor escolhe explicitamente se usa `base_price` ou `pix_price` para aquele item.
- **Quantidade**: campo de quantidade obrigatório ao vincular, com máximo permitido = `stock_quantity` retornado pela API no momento da busca (validação de front-end/back-end).
- **Mesmo produto pode ser vinculado múltiplas vezes** ao mesmo card (cada vínculo é uma linha independente, útil se quiser registrar o mesmo SKU com preços diferentes de buscas diferentes) — não há restrição de unicidade por SKU dentro do card.
- **Valor do card = soma de `unit_price * quantity` de todos os `KanbanCardProduct` vinculados** (soma simples, sem outros ajustes/descontos).
- **Edição do preço pós-vínculo**: na aba Produtos do modal do card, o campo de preço (`unit_price`) de cada linha vinculada é **editável inline só para admins** (agentes normais veem só leitura). Ao salvar, sobrescreve o valor daquele vínculo específico, sem manter histórico do valor anterior. Agentes normais podem livremente adicionar/remover produtos vinculados (só não editam o preço já vinculado).
- **Não implementar** (fora de escopo): vincular conversa a um card manual depois de criado ("Vincular conversa" do mockup) — fica como está hoje (só na criação via `KanbanOpportunityPicker`).

### 4.3 UI da aba "Produtos" no modal do card

- Campo de busca (texto/SKU) + seletor de lista de preço (`default` pré-selecionado).
- Resultados da busca mostrando nome, SKU, marca, preço base e pix, estoque disponível, com botão de adicionar (abre um pequeno formulário de quantidade + escolha de preço pix/base antes de confirmar o vínculo).
- Lista de produtos já vinculados ao card, com nome, sku, quantidade, preço unitário (editável inline se admin), subtotal por linha, botão remover, e total geral do card no rodapé.

## 5. Modal de card (redesign — imagem 6)

- Reaproveita a **navegação por abas real** do mockup, mas **removendo** as abas que não fazem sentido no card atual (Atribuição, Agendamento, Relacionamentos, Notas, Automação) porque já estão centralizadas hoje numa página única.
- Abas finais: **Geral** | **Produtos** | **Dados Adicionais**.
  - **Geral**: todo o conteúdo que já existe hoje no `KanbanOpportunityDetailsModal.vue` (Título, Contato, Descrição, Conversa, Labels, Assignee, Prioridade, Data de vencimento) **+ o badge de status Aberto/Ganho/Perdido** (seção 3) e o **valor total do card** (somado da aba Produtos, exibido como read-only aqui).
  - **Produtos**: nova aba (seção 4.3).
  - **Dados Adicionais**: nova aba — renderiza dinamicamente os campos definidos na aba "Campos Personalizados Globais" daquele funil (seção 2.2). Cada campo aparece com o input correto pro tipo (texto/número/data/boolean; "Lista" vira um input de múltiplos valores livres, ex. tags). Valores salvos em um novo model, ex. `KanbanCardFieldValue` (`kanban_card_id`, `kanban_board_field_id` ou similar, `value` em jsonb pra suportar lista de valores).
- Não implementar aba de Automação nem qualquer funcionalidade de automação.

## 6. Board view (Kanban) — ajustes visuais (imagem 7)

- **Já implementado hoje** (não precisa recriar): fundo pastel por coluna, header colorido, contador de cards, drag-and-drop de cards e estágios, prioridade, data de vencimento, avatar/inbox do contato.
- **Adicionar**:
  - Badge de status (Aberto/Ganho/Perdido) no card, clicável, conforme seção 3.
  - Valor do card (soma dos produtos vinculados) exibido no rodapé do card, ao lado da data.
  - Soma total de valor por coluna, exibida no header do estágio ao lado do contador (ex.: "R$ 150,00").
- **Não incluir** o ícone de raio (⚡) do header de coluna do mockup — decorativo/fora de escopo (sem automação de estágio).

## 7. Modelo de dados — resumo das mudanças (Rails)

Novas colunas:
- `kanban_boards`: `won_stage_id` (bigint, FK `kanban_stages`, nullable), `lost_stage_id` (bigint, FK `kanban_stages`, nullable), `lost_reason_required` (boolean, default false).
- `kanban_stages`: `description` (text, nullable).
- `kanban_cards`: `kanban_reason_id` (bigint, FK nullable, para o motivo de ganho/perda selecionado).

Novos models/tabelas:
- `KanbanCustomField` (por board): `kanban_board_id`, `account_id`, `key`, `field_type` (enum: text/number/date/boolean), `multiple` (boolean, único vs lista), `position`, `active`.
- `KanbanCardFieldValue`: `kanban_card_id`, `kanban_custom_field_id`, `value` (jsonb — array sempre, mesmo pra campo único, pra simplificar).
- `KanbanReason` (por board): `kanban_board_id`, `account_id`, `title`, `description`, `reason_type` (enum: lost/won), `position`, `active`.
- `KanbanCardProduct`: `kanban_card_id`, `account_id`, `sku`, `name`, `brand`, `image_url`, `quantity`, `unit_price`, `price_type` (enum: pix/base), `price_list`, `position`.

Remoção/não-implementação:
- Sem coluna de moeda (`currency`) em `kanban_boards` — fixo BRL/R$ no código.
- Sem coluna/feature de round-robin.

## 8. Fora de escopo (confirmado explicitamente)

- Aba "Metas".
- Aba "Presets de Checklist".
- Aba "Automação" no card.
- Checkbox "Supervisor" em Agentes do Funil (mantém só a seleção de visibilidade atual).
- "Distribuição Automática (Round-robin)".
- Campo "Moeda Padrão" configurável.
- "Vincular conversa" após a criação do card (fica só na criação, como hoje).
- Ícone de raio (⚡) no header da coluna do Kanban.
- Biblioteca compartilhada de campos personalizados ou motivos entre funis diferentes (tudo é por funil).
- Cache/sincronização local do catálogo de produtos.
- Histórico de alterações de preço de produto vinculado.

## 9. Pontos de atenção para a implementação

- Seguir o padrão Enterprise: checar se `kanban_boards`/`kanban_stages`/`kanban_cards` têm overrides em `enterprise/` antes de mexer nos models e controllers.
- Toda nova UI usa exclusivamente classes Tailwind existentes no design system (`n-*` tokens), sem CSS customizado, como já é o padrão do restante do Kanban.
- i18n: atualizar `en/kanban.json` **e** `pt_BR/kanban.json` juntos (exceção ao padrão geral do CLAUDE.md, já estabelecida no histórico deste projeto).
- Migração de dados: nenhuma migração de backfill é necessária para boards/cards existentes — eles continuam funcionando sem status/produtos/campos até serem editados.
