<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import camelcaseKeys from 'camelcase-keys';
import Draggable from 'vuedraggable';

import { useAlert } from 'dashboard/composables';
import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';
import KanbanConversationCard from './KanbanConversationCard.vue';

const route = useRoute();
const router = useRouter();
const { t } = useI18n();

const boards = ref([]);
const selectedBoard = ref(null);
const isFetchingBoards = ref(false);
const isFetchingBoard = ref(false);
const isCreatingBoard = ref(false);
const isCreatingStage = ref(false);
const isUpdatingBoard = ref(false);
const isDeletingBoard = ref(false);
const activeActionKey = ref('');
const hasError = ref(false);
const actionError = ref('');
const newBoardName = ref('');
const newStageName = ref('');
const isEditingBoard = ref(false);
const boardForm = ref({ name: '', description: '' });
const editingStageId = ref(null);
const stageNames = ref({});
const stageColors = ref({});
const cardConversationIds = ref({});
const cardPendingRemoval = ref(null);
const boardPendingRemoval = ref(null);
const stagePendingRemoval = ref(null);
const showRemoveCardConfirmation = ref(false);
const showRemoveBoardConfirmation = ref(false);
const showRemoveStageConfirmation = ref(false);
const defaultStageColor = 'blue';
const newStageColor = ref(defaultStageColor);

const stageColorOptions = [
  {
    value: 'blue',
    headerClass: 'bg-n-blue-9',
    swatchClass: 'bg-n-blue-9',
  },
  {
    value: 'teal',
    headerClass: 'bg-n-teal-9',
    swatchClass: 'bg-n-teal-9',
  },
  {
    value: 'amber',
    headerClass: 'bg-n-amber-9',
    swatchClass: 'bg-n-amber-9',
  },
  {
    value: 'ruby',
    headerClass: 'bg-n-ruby-9',
    swatchClass: 'bg-n-ruby-9',
  },
  {
    value: 'iris',
    headerClass: 'bg-n-iris-9',
    swatchClass: 'bg-n-iris-9',
  },
  {
    value: 'violet',
    headerClass: 'bg-n-violet-9',
    swatchClass: 'bg-n-violet-9',
  },
];

const activeBoardId = computed(() => Number(route.params.boardId) || null);
const stages = computed(() => selectedBoard.value?.stages || []);
const hasBoards = computed(() => boards.value.length > 0);
const isInitialLoading = computed(
  () => isFetchingBoards.value && !selectedBoard.value
);
const stageListModel = computed({
  get: () => selectedBoard.value?.stages || [],
  set: nextStages => {
    if (!selectedBoard.value) return;

    selectedBoard.value = { ...selectedBoard.value, stages: nextStages };
  },
});

const normalizePayload = data => camelcaseKeys(data || {}, { deep: true });

const getErrorMessage = (error, fallbackMessage) =>
  error?.response?.data?.error ||
  error?.response?.data?.message ||
  error?.message ||
  fallbackMessage;

const showActionError = (error, fallbackMessage) => {
  const message = getErrorMessage(error, fallbackMessage);
  actionError.value = message;
  useAlert(message);
};

const getStageColorOption = color =>
  stageColorOptions.find(option => option.value === color) ||
  stageColorOptions[0];

const getStageHeaderClass = stage =>
  getStageColorOption(stage.color).headerClass;

const getStageColorLabel = colorOption => {
  const labels = {
    blue: t('KANBAN.COLORS.BLUE'),
    teal: t('KANBAN.COLORS.TEAL'),
    amber: t('KANBAN.COLORS.AMBER'),
    ruby: t('KANBAN.COLORS.RUBY'),
    iris: t('KANBAN.COLORS.IRIS'),
    violet: t('KANBAN.COLORS.VIOLET'),
  };

  return labels[colorOption.value];
};

const getSelectStageColorLabel = colorOption =>
  t('KANBAN.ACTIONS.SELECT_STAGE_COLOR', {
    color: getStageColorLabel(colorOption),
  });

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

const startEditingBoard = () => {
  if (!selectedBoard.value) return;

  boardForm.value = {
    name: selectedBoard.value.name || '',
    description: selectedBoard.value.description || '',
  };
  isEditingBoard.value = true;
};

const cancelEditingBoard = () => {
  isEditingBoard.value = false;
  boardForm.value = { name: '', description: '' };
};

const updateBoard = async () => {
  const name = boardForm.value.name.trim();
  if (!selectedBoard.value?.id || !name || isUpdatingBoard.value) return;

  isUpdatingBoard.value = true;
  actionError.value = '';

  try {
    const response = await KanbanBoardsAPI.update(selectedBoard.value.id, {
      kanban_board: {
        name,
        description: boardForm.value.description.trim(),
      },
    });
    const board = normalizePayload(response.data);
    selectedBoard.value = { ...selectedBoard.value, ...board };
    boards.value = boards.value.map(existingBoard =>
      existingBoard.id === board.id ? board : existingBoard
    );
    cancelEditingBoard();
    useAlert(t('KANBAN.ACTIONS.UPDATE_BOARD_SUCCESS'));
  } catch (error) {
    showActionError(error, t('KANBAN.ACTIONS.UPDATE_BOARD_ERROR'));
  } finally {
    isUpdatingBoard.value = false;
  }
};

const openRemoveBoardConfirmation = () => {
  if (!selectedBoard.value) return;

  boardPendingRemoval.value = selectedBoard.value;
  showRemoveBoardConfirmation.value = true;
};

const closeRemoveBoardConfirmation = () => {
  showRemoveBoardConfirmation.value = false;
  boardPendingRemoval.value = null;
};

const removeBoard = async board => {
  if (!board?.id || isDeletingBoard.value) return;

  isDeletingBoard.value = true;
  actionError.value = '';

  try {
    await KanbanBoardsAPI.delete(board.id);
    boards.value = boards.value.filter(
      existingBoard => existingBoard.id !== board.id
    );
    const nextBoard = boards.value[0];

    if (nextBoard) {
      await router.replace({
        name: 'kanban_board_show',
        params: {
          accountId: route.params.accountId,
          boardId: nextBoard.id,
        },
      });
      await showBoard(nextBoard.id);
    } else {
      selectedBoard.value = null;
      await router.replace({
        name: 'kanban_boards',
        params: {
          accountId: route.params.accountId,
        },
      });
    }

    cancelEditingBoard();
    useAlert(t('KANBAN.ACTIONS.REMOVE_BOARD_SUCCESS'));
  } catch (error) {
    showActionError(error, t('KANBAN.ACTIONS.REMOVE_BOARD_ERROR'));
  } finally {
    isDeletingBoard.value = false;
  }
};

const confirmRemoveBoard = async () => {
  const board = boardPendingRemoval.value;
  closeRemoveBoardConfirmation();

  if (!board) return;

  await removeBoard(board);
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
    useAlert(t('KANBAN.ACTIONS.CREATE_BOARD_SUCCESS'));
  } catch (error) {
    showActionError(error, t('KANBAN.ACTIONS.CREATE_BOARD_ERROR'));
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
        color: newStageColor.value,
        position: stages.value.length,
      },
    });
    newStageName.value = '';
    newStageColor.value = defaultStageColor;
    await refreshSelectedBoard();
    useAlert(t('KANBAN.ACTIONS.CREATE_STAGE_SUCCESS'));
  } catch (error) {
    showActionError(error, t('KANBAN.ACTIONS.CREATE_STAGE_ERROR'));
  } finally {
    isCreatingStage.value = false;
  }
};

const startEditingStage = stage => {
  editingStageId.value = stage.id;
  stageNames.value = {
    ...stageNames.value,
    [stage.id]: stage.name,
  };
  stageColors.value = {
    ...stageColors.value,
    [stage.id]: getStageColorOption(stage.color).value,
  };
};

const cancelEditingStage = () => {
  editingStageId.value = null;
};

const updateStage = async stage => {
  const name = String(stageNames.value[stage.id] || '').trim();
  const color = stageColors.value[stage.id] || defaultStageColor;
  if (!selectedBoard.value?.id || !name || activeActionKey.value) return;

  activeActionKey.value = `update-stage-${stage.id}`;
  actionError.value = '';

  try {
    await KanbanBoardsAPI.updateStage(selectedBoard.value.id, stage.id, {
      stage: {
        name,
        color,
      },
    });
    cancelEditingStage();
    await refreshSelectedBoard();
    useAlert(t('KANBAN.ACTIONS.UPDATE_STAGE_SUCCESS'));
  } catch (error) {
    showActionError(error, t('KANBAN.ACTIONS.UPDATE_STAGE_ERROR'));
  } finally {
    activeActionKey.value = '';
  }
};

const openRemoveStageConfirmation = stage => {
  if (stage.cards.length > 0) {
    showActionError(null, t('KANBAN.ACTIONS.REMOVE_STAGE_NOT_EMPTY'));
    return;
  }

  stagePendingRemoval.value = stage;
  showRemoveStageConfirmation.value = true;
};

const closeRemoveStageConfirmation = () => {
  showRemoveStageConfirmation.value = false;
  stagePendingRemoval.value = null;
};

const removeStage = async stage => {
  if (!selectedBoard.value?.id || !stage?.id || activeActionKey.value) return;

  activeActionKey.value = `remove-stage-${stage.id}`;
  actionError.value = '';

  try {
    await KanbanBoardsAPI.deleteStage(selectedBoard.value.id, stage.id);
    await refreshSelectedBoard();
    useAlert(t('KANBAN.ACTIONS.REMOVE_STAGE_SUCCESS'));
  } catch (error) {
    showActionError(error, t('KANBAN.ACTIONS.REMOVE_STAGE_ERROR'));
  } finally {
    activeActionKey.value = '';
  }
};

const confirmRemoveStage = async () => {
  const stage = stagePendingRemoval.value;
  closeRemoveStageConfirmation();

  if (!stage) return;

  await removeStage(stage);
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
    useAlert(t('KANBAN.ACTIONS.ADD_CARD_SUCCESS'));
  } catch (error) {
    showActionError(error, t('KANBAN.ACTIONS.ADD_CARD_ERROR'));
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
    useAlert(t('KANBAN.ACTIONS.MOVE_CARD_SUCCESS'));
  } catch (error) {
    showActionError(error, t('KANBAN.ACTIONS.MOVE_CARD_ERROR'));
  } finally {
    activeActionKey.value = '';
  }
};

const reorderCard = async (card, direction) => {
  if (
    !selectedBoard.value?.id ||
    !card?.conversationId ||
    activeActionKey.value
  ) {
    return;
  }

  activeActionKey.value = `reorder-card-${card.id}`;
  actionError.value = '';

  try {
    await KanbanBoardsAPI.reorderCard(
      selectedBoard.value.id,
      card.conversationId,
      direction
    );
    await refreshSelectedBoard();
    useAlert(t('KANBAN.ACTIONS.REORDER_CARD_SUCCESS'));
  } catch (error) {
    showActionError(error, t('KANBAN.ACTIONS.REORDER_CARD_ERROR'));
  } finally {
    activeActionKey.value = '';
  }
};

const reorderStageByPosition = async (stage, position) => {
  if (!selectedBoard.value?.id || !stage?.id || activeActionKey.value) return;

  activeActionKey.value = `reorder-stage-${stage.id}`;
  actionError.value = '';

  try {
    await KanbanBoardsAPI.reorderStage(selectedBoard.value.id, stage.id, {
      position,
    });
    await refreshSelectedBoard();
  } catch (error) {
    showActionError(error, t('KANBAN.ACTIONS.REORDER_STAGE_ERROR'));
    await refreshSelectedBoard();
  } finally {
    activeActionKey.value = '';
  }
};

const onStageDragEnd = async event => {
  const stageId = Number(event?.item?.dataset?.stageId);
  const newIndex = event?.newIndex;
  const oldIndex = event?.oldIndex;
  if (!stageId || oldIndex === newIndex || newIndex === undefined) return;

  const stage = stages.value.find(item => item.id === stageId);
  if (!stage) return;

  await reorderStageByPosition(stage, newIndex + 1);
};

const onCardDragChange = async (stage, event) => {
  const card = event?.added?.element || event?.moved?.element;
  const targetIndex = event?.added?.newIndex ?? event?.moved?.newIndex;
  if (
    !selectedBoard.value?.id ||
    !stage?.id ||
    !card ||
    targetIndex === undefined
  ) {
    return;
  }

  const destinationPosition = targetIndex + 1;
  const stageChanged = card.kanbanStageId !== stage.id;
  const positionChanged = card.position !== destinationPosition;
  if (!stageChanged && !positionChanged) return;

  activeActionKey.value = `reorder-card-${card.id}`;
  actionError.value = '';

  try {
    await KanbanBoardsAPI.reorderCard(
      selectedBoard.value.id,
      card.conversationId,
      {
        card: {
          kanban_stage_id: stage.id,
          position: destinationPosition,
        },
      }
    );
    await refreshSelectedBoard();
  } catch (error) {
    showActionError(error, t('KANBAN.ACTIONS.REORDER_CARD_ERROR'));
    await refreshSelectedBoard();
  } finally {
    activeActionKey.value = '';
  }
};

const openRemoveCardConfirmation = card => {
  cardPendingRemoval.value = card;
  showRemoveCardConfirmation.value = true;
};

const closeRemoveCardConfirmation = () => {
  showRemoveCardConfirmation.value = false;
  cardPendingRemoval.value = null;
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
    useAlert(t('KANBAN.ACTIONS.REMOVE_CARD_SUCCESS'));
  } catch (error) {
    showActionError(error, t('KANBAN.ACTIONS.REMOVE_CARD_ERROR'));
  } finally {
    activeActionKey.value = '';
  }
};

const confirmRemoveCard = async () => {
  const card = cardPendingRemoval.value;
  closeRemoveCardConfirmation();

  if (!card) return;

  await removeCard(card);
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

const removeCardMessageValue = computed(() => {
  if (!cardPendingRemoval.value) return '';

  return getContactName(cardPendingRemoval.value);
});

const removeBoardMessageValue = computed(
  () => boardPendingRemoval.value?.name || ''
);
const removeStageMessageValue = computed(
  () => stagePendingRemoval.value?.name || ''
);

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
        {{ t('KANBAN.EMPTY_BOARDS_DESCRIPTION') }}
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
        class="flex min-h-16 flex-wrap items-center justify-between gap-4 border-b border-n-weak px-6 py-3"
      >
        <div class="min-w-0 flex-1">
          <form
            v-if="selectedBoard && isEditingBoard"
            class="grid max-w-xl gap-2"
            @submit.prevent="updateBoard"
          >
            <input
              v-model="boardForm.name"
              type="text"
              class="min-w-0 rounded-md border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 outline-none placeholder:text-n-slate-10 focus:border-n-brand"
              :placeholder="t('KANBAN.ACTIONS.BOARD_NAME_PLACEHOLDER')"
            />
            <input
              v-model="boardForm.description"
              type="text"
              class="min-w-0 rounded-md border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 outline-none placeholder:text-n-slate-10 focus:border-n-brand"
              :placeholder="t('KANBAN.ACTIONS.BOARD_DESCRIPTION_PLACEHOLDER')"
            />
            <div class="flex gap-2">
              <button
                type="submit"
                class="rounded-md bg-n-brand px-3 py-2 text-sm font-medium text-white disabled:cursor-not-allowed disabled:opacity-50"
                :disabled="!boardForm.name.trim() || isUpdatingBoard"
              >
                {{ t('KANBAN.ACTIONS.SAVE_BOARD') }}
              </button>
              <button
                type="button"
                class="rounded-md border border-n-weak px-3 py-2 text-sm font-medium text-n-slate-12"
                @click="cancelEditingBoard"
              >
                {{ t('KANBAN.ACTIONS.CANCEL') }}
              </button>
            </div>
          </form>
          <template v-else>
            <h2 class="truncate text-xl font-medium text-n-slate-12">
              {{ selectedBoard?.name || t('KANBAN.NO_BOARD_SELECTED') }}
            </h2>
            <p
              v-if="selectedBoard?.description"
              class="truncate text-sm text-n-slate-11"
            >
              {{ selectedBoard.description }}
            </p>
          </template>
        </div>
        <div v-if="selectedBoard && !isEditingBoard" class="flex gap-2">
          <button
            type="button"
            class="rounded-md border border-n-weak px-3 py-2 text-sm font-medium text-n-slate-12 disabled:cursor-not-allowed disabled:opacity-50"
            :disabled="isDeletingBoard"
            @click="startEditingBoard"
          >
            {{ t('KANBAN.ACTIONS.EDIT_BOARD') }}
          </button>
          <button
            type="button"
            class="rounded-md border border-n-weak px-3 py-2 text-sm font-medium text-n-ruby-11 disabled:cursor-not-allowed disabled:opacity-50"
            :disabled="isDeletingBoard"
            @click="openRemoveBoardConfirmation"
          >
            {{ t('KANBAN.ACTIONS.REMOVE_BOARD') }}
          </button>
        </div>
        <form
          v-if="selectedBoard"
          class="grid w-full max-w-md flex-shrink-0 gap-2"
          @submit.prevent="createStage"
        >
          <div class="flex gap-2">
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
          </div>
          <div
            class="flex items-center gap-1.5"
            :aria-label="t('KANBAN.ACTIONS.STAGE_COLOR')"
          >
            <button
              v-for="colorOption in stageColorOptions"
              :key="colorOption.value"
              type="button"
              class="size-5 rounded-full border border-n-weak ring-offset-2 ring-offset-n-surface-1"
              :class="[
                colorOption.swatchClass,
                newStageColor === colorOption.value
                  ? 'ring-2 ring-n-slate-12'
                  : 'hover:ring-2 hover:ring-n-slate-8',
              ]"
              :aria-label="getSelectStageColorLabel(colorOption)"
              @click="newStageColor = colorOption.value"
            />
          </div>
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
        class="flex flex-1 items-center justify-center p-6 text-center"
      >
        <div class="max-w-md">
          <h3 class="text-base font-medium text-n-slate-12">
            {{ t('KANBAN.EMPTY_BOARDS') }}
          </h3>
          <p class="mt-2 text-sm text-n-slate-11">
            {{ t('KANBAN.EMPTY_BOARDS_DESCRIPTION') }}
          </p>
        </div>
      </div>

      <div
        v-else-if="hasBoards && stages.length === 0"
        class="flex flex-1 items-center justify-center p-6 text-center"
      >
        <div class="max-w-md">
          <h3 class="text-base font-medium text-n-slate-12">
            {{ t('KANBAN.EMPTY_STAGES') }}
          </h3>
          <p class="mt-2 text-sm text-n-slate-11">
            {{ t('KANBAN.EMPTY_STAGES_DESCRIPTION') }}
          </p>
        </div>
      </div>

      <div v-else class="flex min-h-0 flex-1 overflow-x-auto p-4">
        <Draggable
          v-model="stageListModel"
          item-key="id"
          class="flex min-h-0 gap-4"
          handle=".stage-drag-handle"
          ghost-class="opacity-60"
          chosen-class="opacity-90"
          :animation="180"
          @end="onStageDragEnd"
        >
          <template #item="{ element: stage }">
            <section
              :data-stage-id="stage.id"
              class="flex w-80 flex-shrink-0 flex-col overflow-hidden rounded-lg border border-n-weak bg-n-solid-1"
            >
              <header
                class="flex min-h-14 items-center justify-between gap-2 px-3 py-2 text-white"
                :class="getStageHeaderClass(stage)"
              >
                <form
                  v-if="editingStageId === stage.id"
                  class="grid min-w-0 flex-1 gap-2"
                  @submit.prevent="updateStage(stage)"
                >
                  <div class="flex min-w-0 gap-2">
                    <input
                      v-model="stageNames[stage.id]"
                      type="text"
                      class="min-w-0 flex-1 rounded-md border border-white/30 bg-white/90 px-2 py-1.5 text-sm text-n-slate-12 outline-none focus:border-white"
                      :placeholder="t('KANBAN.ACTIONS.STAGE_NAME_PLACEHOLDER')"
                    />
                    <button
                      type="submit"
                      class="rounded-md border border-white/30 bg-white/10 px-2 py-1.5 text-xs font-medium text-white disabled:cursor-not-allowed disabled:opacity-50"
                      :disabled="
                        !String(stageNames[stage.id] || '').trim() ||
                        !!activeActionKey
                      "
                    >
                      {{ t('KANBAN.ACTIONS.SAVE_STAGE') }}
                    </button>
                    <button
                      type="button"
                      class="rounded-md border border-white/30 bg-white/10 px-2 py-1.5 text-xs font-medium text-white"
                      @click="cancelEditingStage"
                    >
                      {{ t('KANBAN.ACTIONS.CANCEL') }}
                    </button>
                  </div>
                  <div
                    class="flex items-center gap-1.5"
                    :aria-label="t('KANBAN.ACTIONS.STAGE_COLOR')"
                  >
                    <button
                      v-for="colorOption in stageColorOptions"
                      :key="colorOption.value"
                      type="button"
                      class="size-5 rounded-full border border-white/40 ring-offset-2"
                      :class="[
                        colorOption.swatchClass,
                        stageColors[stage.id] === colorOption.value
                          ? 'ring-2 ring-white'
                          : 'hover:ring-2 hover:ring-white/70',
                      ]"
                      :aria-label="getSelectStageColorLabel(colorOption)"
                      @click="stageColors[stage.id] = colorOption.value"
                    />
                  </div>
                </form>
                <template v-else>
                  <div class="flex min-w-0 flex-1 items-center gap-2">
                    <span
                      class="stage-drag-handle flex-shrink-0 cursor-grab rounded border border-white/30 bg-white/10 p-1 text-white/80"
                    >
                      <i class="i-lucide-grip-horizontal size-3.5" />
                    </span>
                    <h3 class="truncate text-sm font-medium">
                      {{ stage.name }}
                    </h3>
                    <span
                      class="flex-shrink-0 rounded-full bg-white/20 px-2 py-0.5 text-xs font-medium"
                    >
                      {{ stage.cards.length }}
                    </span>
                  </div>
                  <div class="flex flex-shrink-0 gap-1">
                    <button
                      type="button"
                      class="flex size-8 items-center justify-center rounded-md border border-white/30 bg-white/10 text-white hover:bg-white/20 disabled:cursor-not-allowed disabled:opacity-50"
                      :disabled="!!activeActionKey"
                      :aria-label="t('KANBAN.ACTIONS.EDIT_STAGE')"
                      @click="startEditingStage(stage)"
                    >
                      <i class="i-lucide-pencil size-4" />
                    </button>
                    <button
                      type="button"
                      class="flex size-8 items-center justify-center rounded-md border border-white/30 bg-white/10 text-white hover:bg-white/20 disabled:cursor-not-allowed disabled:opacity-50"
                      :disabled="!!activeActionKey"
                      :aria-label="t('KANBAN.ACTIONS.REMOVE_STAGE')"
                      @click="openRemoveStageConfirmation(stage)"
                    >
                      <i class="i-lucide-x size-4" />
                    </button>
                  </div>
                </template>
              </header>

              <div
                class="flex min-h-0 flex-1 flex-col gap-2 overflow-y-auto bg-n-solid-1 p-3"
              >
                <form class="flex gap-2" @submit.prevent="addCard(stage)">
                  <input
                    v-model="cardConversationIds[stage.id]"
                    type="number"
                    min="1"
                    class="min-w-0 flex-1 rounded-md border border-n-weak bg-n-surface-2 px-3 py-2 text-sm text-n-slate-12 outline-none placeholder:text-n-slate-10 focus:border-n-brand"
                    :placeholder="
                      t('KANBAN.ACTIONS.CONVERSATION_ID_PLACEHOLDER')
                    "
                  />
                  <button
                    type="submit"
                    class="flex flex-shrink-0 items-center gap-1 rounded-md border border-n-weak bg-n-alpha-1 px-3 py-2 text-sm font-medium text-n-slate-12 hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-50"
                    :disabled="
                      !String(cardConversationIds[stage.id] || '').trim() ||
                      !!activeActionKey
                    "
                  >
                    <i class="i-lucide-plus size-4" />
                    {{ t('KANBAN.ACTIONS.ADD_CARD') }}
                  </button>
                </form>

                <p
                  v-if="stage.cards.length === 0"
                  class="px-1 py-2 text-sm text-n-slate-10"
                >
                  {{ t('KANBAN.EMPTY_CARDS') }}
                </p>

                <Draggable
                  :list="stage.cards"
                  item-key="id"
                  :group="{ name: 'kanban-cards' }"
                  handle=".card-drag-handle"
                  ghost-class="opacity-60"
                  chosen-class="opacity-90"
                  :animation="180"
                  @change="onCardDragChange(stage, $event)"
                >
                  <template #item="{ element: card, index: cardIndex }">
                    <KanbanConversationCard
                      :card="card"
                      :stages="stages"
                      :active-action-key="activeActionKey"
                      :is-first="cardIndex === 0"
                      :is-last="cardIndex === stage.cards.length - 1"
                      @move-card="moveCard"
                      @open-conversation="openConversation"
                      @remove-card="openRemoveCardConfirmation"
                      @reorder-card="reorderCard"
                    />
                  </template>
                </Draggable>
              </div>
            </section>
          </template>
        </Draggable>
      </div>
    </section>

    <woot-delete-modal
      v-model:show="showRemoveCardConfirmation"
      :on-close="closeRemoveCardConfirmation"
      :on-confirm="confirmRemoveCard"
      :title="t('KANBAN.REMOVE_CARD.TITLE')"
      :message="t('KANBAN.REMOVE_CARD.MESSAGE')"
      :message-value="removeCardMessageValue"
      :confirm-text="t('KANBAN.REMOVE_CARD.CONFIRM')"
      :reject-text="t('KANBAN.REMOVE_CARD.CANCEL')"
    />
    <woot-delete-modal
      v-model:show="showRemoveBoardConfirmation"
      :on-close="closeRemoveBoardConfirmation"
      :on-confirm="confirmRemoveBoard"
      :title="t('KANBAN.REMOVE_BOARD.TITLE')"
      :message="t('KANBAN.REMOVE_BOARD.MESSAGE')"
      :message-value="removeBoardMessageValue"
      :confirm-text="t('KANBAN.REMOVE_BOARD.CONFIRM')"
      :reject-text="t('KANBAN.REMOVE_BOARD.CANCEL')"
    />
    <woot-delete-modal
      v-model:show="showRemoveStageConfirmation"
      :on-close="closeRemoveStageConfirmation"
      :on-confirm="confirmRemoveStage"
      :title="t('KANBAN.REMOVE_STAGE.TITLE')"
      :message="t('KANBAN.REMOVE_STAGE.MESSAGE')"
      :message-value="removeStageMessageValue"
      :confirm-text="t('KANBAN.REMOVE_STAGE.CONFIRM')"
      :reject-text="t('KANBAN.REMOVE_STAGE.CANCEL')"
    />
  </main>
</template>
