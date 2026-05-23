<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import camelcaseKeys from 'camelcase-keys';

import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';

const route = useRoute();
const router = useRouter();
const { t } = useI18n();

const boards = ref([]);
const selectedBoard = ref(null);
const isFetchingBoards = ref(false);
const isFetchingBoard = ref(false);
const isCreatingBoard = ref(false);
const isCreatingStage = ref(false);
const activeActionKey = ref('');
const hasError = ref(false);
const actionError = ref('');
const newBoardName = ref('');
const newStageName = ref('');
const cardConversationIds = ref({});

const activeBoardId = computed(() => Number(route.params.boardId) || null);
const stages = computed(() => selectedBoard.value?.stages || []);
const hasBoards = computed(() => boards.value.length > 0);
const isInitialLoading = computed(
  () => isFetchingBoards.value && !selectedBoard.value
);

const normalizePayload = data => camelcaseKeys(data || {}, { deep: true });

const setActionError = () => {
  actionError.value = t('KANBAN.ACTIONS.ERROR');
};

const showBoard = async boardId => {
  if (!boardId) {
    selectedBoard.value = null;
    return;
  }

  isFetchingBoard.value = true;
  hasError.value = false;

  try {
    const response = await KanbanBoardsAPI.show(boardId);
    selectedBoard.value = normalizePayload(response.data);
  } catch {
    hasError.value = true;
    selectedBoard.value = null;
  } finally {
    isFetchingBoard.value = false;
  }
};

const refreshSelectedBoard = async () => {
  if (!selectedBoard.value?.id) return;

  await showBoard(selectedBoard.value.id);
};

const createBoard = async () => {
  const name = newBoardName.value.trim();
  if (!name || isCreatingBoard.value) return;

  isCreatingBoard.value = true;
  actionError.value = '';

  try {
    const response = await KanbanBoardsAPI.create({
      kanban_board: {
        name,
        position: boards.value.length,
      },
    });
    const board = normalizePayload(response.data);
    boards.value = [...boards.value, board];
    selectedBoard.value = { ...board, stages: [] };
    newBoardName.value = '';
    router.push({
      name: 'kanban_board_show',
      params: {
        accountId: route.params.accountId,
        boardId: board.id,
      },
    });
  } catch {
    setActionError();
  } finally {
    isCreatingBoard.value = false;
  }
};

const createStage = async () => {
  const name = newStageName.value.trim();
  if (!selectedBoard.value?.id || !name || isCreatingStage.value) return;

  isCreatingStage.value = true;
  actionError.value = '';

  try {
    await KanbanBoardsAPI.createStage(selectedBoard.value.id, {
      stage: {
        name,
        position: stages.value.length,
      },
    });
    newStageName.value = '';
    await refreshSelectedBoard();
  } catch {
    setActionError();
  } finally {
    isCreatingStage.value = false;
  }
};

const addCard = async stage => {
  const conversationId = String(
    cardConversationIds.value[stage.id] || ''
  ).trim();
  const actionKey = `add-card-${stage.id}`;
  if (!selectedBoard.value?.id || !conversationId || activeActionKey.value) {
    return;
  }

  activeActionKey.value = actionKey;
  actionError.value = '';

  try {
    await KanbanBoardsAPI.createCard(selectedBoard.value.id, {
      card: {
        conversation_id: conversationId,
        kanban_stage_id: stage.id,
      },
    });
    cardConversationIds.value = {
      ...cardConversationIds.value,
      [stage.id]: '',
    };
    await refreshSelectedBoard();
  } catch {
    setActionError();
  } finally {
    activeActionKey.value = '';
  }
};

const moveCard = async (card, kanbanStageId) => {
  const nextStageId = Number(kanbanStageId);
  if (
    !selectedBoard.value?.id ||
    !nextStageId ||
    nextStageId === card.kanbanStageId ||
    activeActionKey.value
  ) {
    return;
  }

  activeActionKey.value = `move-card-${card.id}`;
  actionError.value = '';

  try {
    await KanbanBoardsAPI.updateCard(
      selectedBoard.value.id,
      card.conversationId,
      {
        card: {
          kanban_stage_id: nextStageId,
        },
      }
    );
    await refreshSelectedBoard();
  } catch {
    setActionError();
  } finally {
    activeActionKey.value = '';
  }
};

const removeCard = async card => {
  if (!selectedBoard.value?.id || activeActionKey.value) return;

  activeActionKey.value = `remove-card-${card.id}`;
  actionError.value = '';

  try {
    await KanbanBoardsAPI.deleteCard(
      selectedBoard.value.id,
      card.conversationId
    );
    await refreshSelectedBoard();
  } catch {
    setActionError();
  } finally {
    activeActionKey.value = '';
  }
};

const selectBoard = boardId => {
  if (boardId === activeBoardId.value) return;

  router.push({
    name: 'kanban_board_show',
    params: {
      accountId: route.params.accountId,
      boardId,
    },
  });
};

const fetchBoards = async () => {
  isFetchingBoards.value = true;
  hasError.value = false;

  try {
    const response = await KanbanBoardsAPI.get();
    boards.value = response.data.map(board => normalizePayload(board));

    const nextBoardId = activeBoardId.value || boards.value[0]?.id;
    if (nextBoardId && !activeBoardId.value) {
      router.replace({
        name: 'kanban_board_show',
        params: {
          accountId: route.params.accountId,
          boardId: nextBoardId,
        },
      });
      return;
    }

    await showBoard(nextBoardId);
  } catch {
    hasError.value = true;
    boards.value = [];
    selectedBoard.value = null;
  } finally {
    isFetchingBoards.value = false;
  }
};

const getContactName = card =>
  card.conversation?.meta?.sender?.name || t('KANBAN.CARD.UNKNOWN_CONTACT');

const getLastMessage = card =>
  card.conversation?.messages?.[0]?.content || t('KANBAN.CARD.NO_MESSAGES');

const getConversationStatus = card =>
  card.conversation?.status || t('KANBAN.CARD.UNKNOWN_STATUS');

const openConversation = (card, event) => {
  const path = frontendURL(
    conversationUrl({
      accountId: route.params.accountId,
      id: card.conversationId,
    })
  );

  if (event.metaKey || event.ctrlKey) {
    window.open(
      `${window.chatwootConfig.hostURL}${path}`,
      '_blank',
      'noopener noreferrer nofollow'
    );
    return;
  }

  router.push({ path });
};

watch(activeBoardId, boardId => {
  if (!boards.value.length) return;
  showBoard(boardId);
});

onMounted(fetchBoards);
</script>

<template>
  <main class="flex h-full min-h-0 w-full bg-n-surface-1 text-n-slate-12">
    <aside
      class="flex w-72 flex-shrink-0 flex-col border-r border-n-weak bg-n-surface-2"
    >
      <div class="border-b border-n-weak px-4 py-4">
        <h1 class="text-lg font-medium text-n-slate-12">
          {{ t('KANBAN.HEADER') }}
        </h1>
        <form class="mt-3 flex gap-2" @submit.prevent="createBoard">
          <input
            v-model="newBoardName"
            type="text"
            class="min-w-0 flex-1 rounded-md border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 outline-none placeholder:text-n-slate-10 focus:border-n-brand"
            :placeholder="t('KANBAN.ACTIONS.BOARD_NAME_PLACEHOLDER')"
          />
          <button
            type="submit"
            class="flex-shrink-0 rounded-md bg-n-brand px-3 py-2 text-sm font-medium text-white disabled:cursor-not-allowed disabled:opacity-50"
            :disabled="!newBoardName.trim() || isCreatingBoard"
          >
            {{ t('KANBAN.ACTIONS.CREATE_BOARD') }}
          </button>
        </form>
      </div>

      <div v-if="isFetchingBoards" class="px-4 py-3 text-sm text-n-slate-11">
        {{ t('KANBAN.LOADING_BOARDS') }}
      </div>

      <div v-else-if="!hasBoards" class="px-4 py-3 text-sm text-n-slate-11">
        {{ t('KANBAN.EMPTY_BOARDS') }}
      </div>

      <nav v-else class="flex flex-col gap-1 overflow-y-auto p-2">
        <button
          v-for="board in boards"
          :key="board.id"
          type="button"
          class="flex min-h-10 w-full items-center rounded-lg px-3 py-2 text-left text-sm transition-colors"
          :class="
            board.id === activeBoardId
              ? 'bg-n-alpha-2 text-n-slate-12'
              : 'text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12'
          "
          @click="selectBoard(board.id)"
        >
          <span class="truncate">{{ board.name }}</span>
        </button>
      </nav>
    </aside>

    <section class="flex min-w-0 flex-1 flex-col">
      <header
        class="flex min-h-16 items-center justify-between gap-4 border-b border-n-weak px-6"
      >
        <div class="min-w-0">
          <h2 class="truncate text-xl font-medium text-n-slate-12">
            {{ selectedBoard?.name || t('KANBAN.NO_BOARD_SELECTED') }}
          </h2>
          <p
            v-if="selectedBoard?.description"
            class="truncate text-sm text-n-slate-11"
          >
            {{ selectedBoard.description }}
          </p>
        </div>
        <form
          v-if="selectedBoard"
          class="flex w-full max-w-md flex-shrink-0 gap-2"
          @submit.prevent="createStage"
        >
          <input
            v-model="newStageName"
            type="text"
            class="min-w-0 flex-1 rounded-md border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 outline-none placeholder:text-n-slate-10 focus:border-n-brand"
            :placeholder="t('KANBAN.ACTIONS.STAGE_NAME_PLACEHOLDER')"
          />
          <button
            type="submit"
            class="flex-shrink-0 rounded-md border border-n-weak px-3 py-2 text-sm font-medium text-n-slate-12 disabled:cursor-not-allowed disabled:opacity-50"
            :disabled="!newStageName.trim() || isCreatingStage"
          >
            {{ t('KANBAN.ACTIONS.CREATE_STAGE') }}
          </button>
        </form>
      </header>

      <div
        v-if="actionError"
        class="border-b border-n-weak bg-n-ruby-2 px-6 py-2 text-sm text-n-ruby-11"
      >
        {{ actionError }}
      </div>

      <div
        v-if="hasError"
        class="flex flex-1 items-center justify-center p-6 text-sm text-n-ruby-11"
      >
        {{ t('KANBAN.ERROR') }}
      </div>

      <div
        v-else-if="isInitialLoading || isFetchingBoard"
        class="flex flex-1 items-center justify-center p-6 text-sm text-n-slate-11"
      >
        {{ t('KANBAN.LOADING_BOARD') }}
      </div>

      <div
        v-else-if="!hasBoards"
        class="flex flex-1 items-center justify-center p-6 text-sm text-n-slate-11"
      >
        {{ t('KANBAN.EMPTY_BOARDS') }}
      </div>

      <div
        v-else-if="hasBoards && stages.length === 0"
        class="flex flex-1 items-center justify-center p-6 text-sm text-n-slate-11"
      >
        {{ t('KANBAN.EMPTY_STAGES') }}
      </div>

      <div v-else class="flex min-h-0 flex-1 gap-4 overflow-x-auto p-4">
        <section
          v-for="stage in stages"
          :key="stage.id"
          class="flex w-80 flex-shrink-0 flex-col rounded-lg border border-n-weak bg-n-surface-2"
        >
          <header
            class="flex min-h-12 items-center justify-between border-b border-n-weak px-3"
          >
            <h3 class="truncate text-sm font-medium text-n-slate-12">
              {{ stage.name }}
            </h3>
            <span class="text-xs text-n-slate-10">
              {{ stage.cards.length }}
            </span>
          </header>

          <div class="flex min-h-0 flex-1 flex-col gap-2 overflow-y-auto p-3">
            <form class="flex gap-2" @submit.prevent="addCard(stage)">
              <input
                v-model="cardConversationIds[stage.id]"
                type="number"
                min="1"
                class="min-w-0 flex-1 rounded-md border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 outline-none placeholder:text-n-slate-10 focus:border-n-brand"
                :placeholder="t('KANBAN.ACTIONS.CONVERSATION_ID_PLACEHOLDER')"
              />
              <button
                type="submit"
                class="flex-shrink-0 rounded-md border border-n-weak px-3 py-2 text-sm font-medium text-n-slate-12 disabled:cursor-not-allowed disabled:opacity-50"
                :disabled="
                  !String(cardConversationIds[stage.id] || '').trim() ||
                  !!activeActionKey
                "
              >
                {{ t('KANBAN.ACTIONS.ADD_CARD') }}
              </button>
            </form>

            <p
              v-if="stage.cards.length === 0"
              class="px-1 py-2 text-sm text-n-slate-10"
            >
              {{ t('KANBAN.EMPTY_CARDS') }}
            </p>

            <article
              v-for="card in stage.cards"
              :key="card.id"
              class="rounded-lg border border-n-weak bg-n-surface-1 p-3"
            >
              <button
                type="button"
                class="w-full text-left"
                :aria-label="
                  t('KANBAN.CARD.OPEN_CONVERSATION', {
                    contactName: getContactName(card),
                  })
                "
                @click="openConversation(card, $event)"
              >
                <div class="flex items-start justify-between gap-2">
                  <h4
                    class="min-w-0 truncate text-sm font-medium text-n-slate-12"
                  >
                    {{ getContactName(card) }}
                  </h4>
                  <span class="flex-shrink-0 text-xs text-n-slate-10">
                    {{
                      t('KANBAN.CARD.CONVERSATION_ID', {
                        id: card.conversationId,
                      })
                    }}
                  </span>
                </div>

                <p class="mt-2 line-clamp-2 text-sm text-n-slate-11">
                  {{ getLastMessage(card) }}
                </p>
              </button>

              <div class="mt-3 flex items-center justify-between gap-2">
                <span
                  class="rounded-md bg-n-alpha-2 px-2 py-1 text-xs text-n-slate-11"
                >
                  {{ getConversationStatus(card) }}
                </span>
                <span
                  v-if="card.conversation?.priority"
                  class="truncate text-xs text-n-slate-10"
                >
                  {{ card.conversation.priority }}
                </span>
              </div>

              <div class="mt-3 flex items-center gap-2">
                <select
                  class="min-w-0 flex-1 rounded-md border border-n-weak bg-n-surface-1 px-2 py-2 text-sm text-n-slate-12 outline-none focus:border-n-brand"
                  :value="card.kanbanStageId"
                  :disabled="!!activeActionKey"
                  :aria-label="t('KANBAN.ACTIONS.MOVE_CARD')"
                  @change="moveCard(card, $event.target.value)"
                >
                  <option
                    v-for="targetStage in stages"
                    :key="targetStage.id"
                    :value="targetStage.id"
                  >
                    {{ targetStage.name }}
                  </option>
                </select>

                <button
                  type="button"
                  class="flex-shrink-0 rounded-md border border-n-weak px-3 py-2 text-sm font-medium text-n-ruby-11 disabled:cursor-not-allowed disabled:opacity-50"
                  :disabled="!!activeActionKey"
                  @click="removeCard(card)"
                >
                  {{ t('KANBAN.ACTIONS.REMOVE_CARD') }}
                </button>
              </div>
            </article>
          </div>
        </section>
      </div>
    </section>
  </main>
</template>
