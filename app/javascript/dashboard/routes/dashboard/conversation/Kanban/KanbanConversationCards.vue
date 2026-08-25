<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import camelcaseKeys from 'camelcase-keys';

import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useKanbanCardFields } from 'dashboard/composables/useKanbanCardFields';
import { useSlaClock } from 'dashboard/composables/useSlaClock';
import { getCardStatusChangeErrorMessage } from 'dashboard/helper/kanbanCardStatus';
import { apiErrorMessage } from 'dashboard/helper/kanbanApiError';
import { SLA_STALE, stageSlaStatus } from 'dashboard/helper/kanbanStageSla';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import KanbanOpportunityPanel from 'dashboard/routes/dashboard/kanban/opportunity/KanbanOpportunityPanel.vue';
import KanbanCardMoveDialog from '../../kanban/KanbanCardMoveDialog.vue';
import KanbanConversationCardForm from './KanbanConversationCardForm.vue';
import KanbanConversationCardItem from './KanbanConversationCardItem.vue';

const props = defineProps({
  conversationId: {
    type: [Number, String],
    required: true,
  },
  // The card list stays mounted while the sidebar section is collapsed so the header
  // can show how many opportunities the conversation has.
  isOpen: {
    type: Boolean,
    default: true,
  },
});

const emit = defineEmits(['open-existing', 'summary']);
const { t } = useI18n();
const store = useStore();
const route = useRoute();
const router = useRouter();
const currentChat = useMapGetter('getSelectedChat');
const accountLabels = useMapGetter('labels/getLabels');
const cards = ref([]);
const boards = ref([]);
const isLoading = ref(false);
const isLoadingBoards = ref(false);
const hasError = ref(false);
const boardsError = ref('');
const createError = ref('');
const isFormOpen = ref(false);
const isCreating = ref(false);
const highlightedCardId = ref(null);
const busyCardIds = ref(new Set());
const assigneeStates = ref({});
const cardsAbortController = ref(null);
const boardsAbortController = ref(null);
const createAbortController = ref(null);
const cardsRequestId = ref(0);
const boardsRequestId = ref(0);
const realtimeRefreshQueued = ref(false);
const deleteDialogRef = ref(null);
const cardToDelete = ref(null);
const isDeletingCard = ref(false);
const moveDialogCard = ref(null);
const opportunityCard = ref(null);
const opportunityPanelRef = ref(null);
const slaNow = useSlaClock();
let highlightTimer = null;

const inboxId = computed(() => currentChat.value?.inbox_id);
const inbox = computed(() => {
  const getInboxById = store.getters?.['inboxes/getInboxById'];
  return getInboxById?.(inboxId.value) || {};
});
const contactId = computed(() => currentChat.value?.meta?.sender?.id);
const defaultSubject = computed(() => {
  const contactName =
    currentChat.value?.meta?.sender?.name?.trim() ||
    `Contact #${contactId.value}`;
  const inboxName = inbox.value?.name?.trim() || `Inbox #${inboxId.value}`;

  return `${contactName} - ${inboxName}`;
});
const hasCards = computed(() => cards.value.length > 0);
const staleCardCount = computed(
  () =>
    cards.value.filter(card => {
      const stage = card.kanbanStage || {};
      return (
        stageSlaStatus({
          stageEnteredAt: card.stageEnteredAt,
          slaHours: stage.slaHours,
          now: slaNow.value,
        }) === SLA_STALE
      );
    }).length
);

const normalize = value => camelcaseKeys(value || {}, { deep: true });
const normalizeCard = response =>
  normalize(response?.data?.payload || response?.data);
const normalizeCollection = response =>
  normalize(response?.data?.payload || response?.data || []);
const isAbortError = error =>
  error?.name === 'AbortError' || error?.name === 'CanceledError';
// Every payload this component holds went through camelcaseKeys on the way in,
// so the wire's snake_case never reaches here.
const cardBoardId = card => card?.kanbanBoardId || card?.kanbanBoard?.id;
const boardStages = board => board?.stagesSummary || [];
const boardForCard = card => {
  const boardId = cardBoardId(card);
  return (
    boards.value.find(board => Number(board.id) === Number(boardId)) ||
    card.kanbanBoard ||
    {}
  );
};
const stagesForCard = (card, board = boardForCard(card)) => {
  const cardStage = card.kanbanStage || {};
  // The sidebar payload nests the stage instead of sending its id on the card.
  const cardStageId = card.kanbanStageId ?? cardStage.id;

  return boardStages(board).map(stage =>
    Number(stage.id) === Number(cardStageId)
      ? { ...stage, ...cardStage }
      : stage
  );
};
// The conversation comes from the store, which keeps the API's own shape.
const cardInboxId = card =>
  card?.inboxId ?? card?.inbox?.id ?? currentChat.value?.inbox_id;
const isSameCard = (firstCard, secondCard) =>
  Number(firstCard?.id) === Number(secondCard?.id);
const regularStagesFor = card => {
  const board = boardForCard(card);
  const terminalIds = [board?.wonStageId, board?.lostStageId]
    .filter(Boolean)
    .map(Number);

  return boardStages(board).filter(
    stage => stage.active !== false && !terminalIds.includes(Number(stage.id))
  );
};
const patchCard = (cardId, updater) => {
  cards.value = cards.value.map(card =>
    Number(card.id) === Number(cardId) ? updater(card) : card
  );
};
const startAction = cardId => {
  busyCardIds.value = new Set([...busyCardIds.value, Number(cardId)]);
};
const opportunityBoard = computed(() =>
  opportunityCard.value ? boardForCard(opportunityCard.value) : {}
);
const opportunityStages = computed(() =>
  opportunityCard.value
    ? stagesForCard(opportunityCard.value, opportunityBoard.value)
    : []
);
const setAssigneeState = (cardId, value) => {
  assigneeStates.value = {
    ...assigneeStates.value,
    [cardId]: { ...assigneeStates.value[cardId], ...value },
  };
};
const assigneeStateFor = card => assigneeStates.value[card.id] || {};

const labelsForTitles = titles =>
  titles.map(
    title =>
      (accountLabels?.value || []).find(label => label.title === title) || {
        title,
      }
  );
const assigneesForIds = (ids, card) => {
  const knownUsers = assigneeStateFor(card).assignableUsers || [];

  return ids.map(
    id =>
      knownUsers.find(user => Number(user.id) === Number(id)) ||
      card.assignees?.find(assignee => Number(assignee.id) === Number(id)) || {
        id,
      }
  );
};
const cardFields = useKanbanCardFields({
  t,
  boardIdFor: card => Number(boardForCard(card).id),
  patchCard: (card, partial) =>
    patchCard(card.id, current => ({ ...current, ...partial })),
  resolveLabels: labelsForTitles,
  resolveAssignees: assigneesForIds,
  onAssignableUsers: (card, users) =>
    setAssigneeState(card.id, { loaded: true, assignableUsers: users }),
});

// Busy covers both whole-card operations (create, move, delete) and the
// per-field updates the shared composable tracks.
const hasBusyCards = computed(
  () => busyCardIds.value.size > 0 || cardFields.hasPendingUpdates.value
);
const isCardBusy = card =>
  busyCardIds.value.has(Number(card.id)) || cardFields.isCardPending(card);
const moveDialogIsMoving = computed(
  () => !!moveDialogCard.value && isCardBusy(moveDialogCard.value)
);

const loadCards = async () => {
  if (!props.conversationId) return;

  const requestId = cardsRequestId.value + 1;
  cardsRequestId.value = requestId;
  cardsAbortController.value?.abort();
  const controller = new AbortController();
  cardsAbortController.value = controller;
  isLoading.value = true;
  hasError.value = false;

  try {
    const response = await KanbanBoardsAPI.getConversationCards(
      props.conversationId,
      { signal: controller.signal }
    );
    if (requestId !== cardsRequestId.value || controller.signal.aborted) return;

    cards.value = normalizeCollection(response);
    if (
      opportunityCard.value &&
      !cards.value.some(card => isSameCard(card, opportunityCard.value))
    ) {
      opportunityCard.value = null;
    }
    if (
      moveDialogCard.value &&
      !cards.value.some(card => isSameCard(card, moveDialogCard.value))
    ) {
      moveDialogCard.value = null;
    }
  } catch (error) {
    if (isAbortError(error) || requestId !== cardsRequestId.value) return;

    cards.value = [];
    hasError.value = true;
  } finally {
    if (requestId === cardsRequestId.value) {
      isLoading.value = false;
      cardsAbortController.value = null;
      if (
        realtimeRefreshQueued.value &&
        !isFormOpen.value &&
        !hasBusyCards.value
      ) {
        realtimeRefreshQueued.value = false;
        loadCards();
      }
    }
  }
};

const loadBoards = async () => {
  const requestId = boardsRequestId.value + 1;
  boardsRequestId.value = requestId;
  boardsAbortController.value?.abort();
  const controller = new AbortController();
  boardsAbortController.value = controller;
  isLoadingBoards.value = true;
  boardsError.value = '';

  try {
    const response = await KanbanBoardsAPI.getBoards({
      signal: controller.signal,
    });
    if (requestId !== boardsRequestId.value || controller.signal.aborted)
      return;

    boards.value = normalizeCollection(response);
  } catch (error) {
    if (isAbortError(error) || requestId !== boardsRequestId.value) return;

    boardsError.value = apiErrorMessage(
      error,
      t('CONVERSATION_SIDEBAR.KANBAN.ERROR')
    );
  } finally {
    if (requestId === boardsRequestId.value) {
      isLoadingBoards.value = false;
      boardsAbortController.value = null;
    }
  }
};

const refreshCardsFromRealtime = () => {
  if (isFormOpen.value || hasBusyCards.value || isLoading.value) {
    realtimeRefreshQueued.value = true;
    return;
  }
  loadCards();
};
const flushRealtimeRefresh = () => {
  if (
    !realtimeRefreshQueued.value ||
    isFormOpen.value ||
    hasBusyCards.value ||
    isLoading.value
  ) {
    return;
  }

  realtimeRefreshQueued.value = false;
  loadCards();
};
const endAction = cardId => {
  const next = new Set(busyCardIds.value);
  next.delete(Number(cardId));
  busyCardIds.value = next;
  flushRealtimeRefresh();
};
// Field updates settle inside the shared composable, so a queued realtime
// refresh has to wait on its pending set too.
watch(hasBusyCards, busy => {
  if (!busy) flushRealtimeRefresh();
});
const realtimeEvents = new Set([
  'kanban.card.created',
  'kanban.card.updated',
  'kanban.card.deleted',
  'kanban.card.reordered',
]);
const handleRealtimeKanbanEvent = ({ event, data } = {}) => {
  if (!realtimeEvents.has(event)) return;
  const eventConversationId =
    data?.conversation_id ??
    data?.conversationId ??
    data?.card?.conversation_id;
  if (
    eventConversationId &&
    String(eventConversationId) !== String(props.conversationId)
  ) {
    return;
  }
  refreshCardsFromRealtime();
};

const highlightCreatedCard = cardId => {
  if (!cardId) return;
  clearTimeout(highlightTimer);
  highlightedCardId.value = cardId;
  highlightTimer = setTimeout(() => {
    highlightedCardId.value = null;
  }, 2000);
};
const openForm = () => {
  createError.value = '';
  isFormOpen.value = true;
};
const cancelForm = () => {
  createAbortController.value?.abort();
  createAbortController.value = null;
  isCreating.value = false;
  createError.value = '';
  isFormOpen.value = false;
  flushRealtimeRefresh();
};
const createCard = async payload => {
  if (isCreating.value) return;

  const controller = new AbortController();
  createAbortController.value = controller;
  isCreating.value = true;
  createError.value = '';

  try {
    const response = await KanbanBoardsAPI.createConversationCard(
      props.conversationId,
      { card: payload },
      { signal: controller.signal }
    );
    if (controller.signal.aborted) return;

    const createdCard = normalizeCard(response);
    isFormOpen.value = false;
    await loadCards();
    highlightCreatedCard(createdCard?.id);
    useAlert(t('CONVERSATION_SIDEBAR.KANBAN.CREATED'), {
      type: 'link',
      to: window.location.pathname,
      message: t('CONVERSATION_SIDEBAR.KANBAN.OPEN_DETAILS'),
    });
  } catch (error) {
    if (isAbortError(error)) return;
    createError.value = apiErrorMessage(
      error,
      t('CONVERSATION_SIDEBAR.KANBAN.CREATE_ERROR')
    );
  } finally {
    if (createAbortController.value === controller) {
      isCreating.value = false;
      createAbortController.value = null;
    }
  }
};

const openDetails = card => {
  if (!card || isCardBusy(card)) return;

  opportunityCard.value = card;
};
const openMoveDialog = card => {
  if (!card || isCardBusy(card)) return;

  moveDialogCard.value = card;
};
const closeMoveDialog = () => {
  if (!moveDialogIsMoving.value) moveDialogCard.value = null;
};
const closeOpportunityPanel = () => {
  opportunityCard.value = null;
};
// The panel persists every field as it changes, so leaving it never asks and
// the exit has nothing to defer.
const openOpportunityInFunnel = card => {
  const boardId = Number(cardBoardId(card));
  if (!boardId || !card?.id) return;

  closeOpportunityPanel();
  router.push({
    name: 'kanban_board_show',
    params: { accountId: route.params.accountId, boardId },
    query: { card_id: card.id },
  });
};
const onOpportunityUpdated = () => {
  loadCards();
};
const onOpportunityBoardChanged = async ({ boardName } = {}) => {
  closeOpportunityPanel();
  await loadCards();
  useAlert(
    t('KANBAN.CARD.MOVE_BOARD_SUCCESS', {
      board: boardName || t('KANBAN.NO_BOARD_SELECTED'),
    })
  );
};

const moveToStageFromPanel = async (card, targetStageId) => {
  const board = boardForCard(card);
  const boardId = Number(board.id);
  if (!boardId || isCardBusy(card)) return false;

  startAction(card.id);
  try {
    await KanbanBoardsAPI.reorderCardById(boardId, card.id, {
      card: { kanban_stage_id: targetStageId, after_card_id: null },
    });
    return true;
  } catch (error) {
    useAlert(apiErrorMessage(error, t('KANBAN.ACTIONS.REORDER_CARD_ERROR')));
    return false;
  } finally {
    endAction(card.id);
  }
};

const moveCardToBoard = async ({ boardId, stageId }) => {
  const card = moveDialogCard.value;
  const sourceBoardId = Number(cardBoardId(card));
  const targetBoard = boards.value.find(
    board => Number(board.id) === Number(boardId)
  );
  if (!card || !sourceBoardId || !targetBoard || isCardBusy(card)) return false;

  startAction(card.id);
  try {
    await KanbanBoardsAPI.moveCardToBoard(sourceBoardId, card.id, {
      target_kanban_board_id: Number(boardId),
      kanban_stage_id: Number(stageId),
    });
    await loadCards();
    moveDialogCard.value = null;
    useAlert(t('KANBAN.CARD.MOVE_BOARD_SUCCESS', { board: targetBoard.name }));
    return true;
  } catch (error) {
    const errorCode = error?.response?.data?.error;
    if (errorCode === 'card_already_in_target_board') {
      useAlert(
        t('KANBAN.CARD.MOVE_BOARD_ERROR_DUPLICATE', {
          board: targetBoard.name,
        })
      );
    } else if (errorCode === 'inbox_not_allowed') {
      useAlert(
        t('KANBAN.CARD.MOVE_BOARD_ERROR_INBOX', {
          board: targetBoard.name,
        })
      );
    } else {
      useAlert(t('KANBAN.CARD.MOVE_BOARD_ERROR'));
    }
    return false;
  } finally {
    endAction(card.id);
  }
};

const { run: runCardAction } = cardFields;

const updateStage = (card, targetStageId) => {
  const stage = regularStagesFor(card).find(
    item => Number(item.id) === Number(targetStageId)
  );
  if (!stage) return false;

  return runCardAction(card, 'stage', {
    optimistic: {
      kanbanStageId: stage.id,
      kanbanStage: { ...(card.kanbanStage || {}), ...stage },
    },
    request: boardId =>
      KanbanBoardsAPI.reorderCardById(boardId, card.id, {
        card: { kanban_stage_id: stage.id, after_card_id: null },
      }),
    apply: response => {
      const updated = normalizeCard(response);
      return {
        ...(updated?.id ? updated : {}),
        kanbanStageId: updated?.kanbanStageId ?? stage.id,
        kanbanStage: {
          ...(card.kanbanStage || {}),
          ...stage,
          ...(updated?.kanbanStage || {}),
        },
      };
    },
    errorKey: 'KANBAN.ACTIONS.REORDER_CARD_ERROR',
  });
};

const changeStatus = (card, { targetStageId, reasonId, reopen }) => {
  const board = boardForCard(card);
  const targetStage = boardStages(board).find(
    stage => Number(stage.id) === Number(targetStageId)
  );
  const currentStageId = card.kanbanStageId ?? card.kanbanStage?.id;

  return runCardAction(card, 'status', {
    optimistic: {
      kanbanStageId: reopen ? currentStageId : targetStageId,
      kanbanReasonId: reopen ? null : reasonId || null,
      kanbanStage: reopen
        ? card.kanbanStage
        : { ...(card.kanbanStage || {}), ...targetStage },
    },
    request: boardId =>
      reopen
        ? KanbanBoardsAPI.reopenCardById(boardId, card.id)
        : KanbanBoardsAPI.updateCardById(boardId, card.id, {
            card: {
              kanban_stage_id: targetStageId,
              kanban_reason_id: reasonId || null,
            },
          }),
    apply: response => {
      const updated = normalizeCard(response);
      const nextStageId =
        updated?.kanbanStageId ?? (reopen ? currentStageId : targetStageId);
      const nextStage =
        boardStages(board).find(
          stage => Number(stage.id) === Number(nextStageId)
        ) || targetStage;

      return {
        ...(updated?.id ? updated : {}),
        kanbanStageId: nextStageId,
        kanbanReasonId:
          updated?.kanbanReasonId ?? (reopen ? null : reasonId || null),
        kanbanStage: {
          ...(card.kanbanStage || {}),
          ...nextStage,
          ...(updated?.kanbanStage || {}),
        },
      };
    },
    errorKey: actionError =>
      getCardStatusChangeErrorMessage(actionError, { reopen, t }),
  });
};

const updatePriority = (card, value) =>
  cardFields.updateDetail(card, 'priority', value || '');
const updateDueDate = (card, value) =>
  cardFields.updateDetail(card, 'dueAt', value || '');
const updateLabels = (card, titles) => cardFields.updateLabels(card, titles);
const updateAssignees = (card, ids) => cardFields.updateAssignees(card, ids);

const loadAssignees = async card => {
  const state = assigneeStateFor(card);
  if (state.loading || state.loaded) return;
  setAssigneeState(card.id, { loading: true, error: '' });

  try {
    const response = await KanbanBoardsAPI.getCardAssignees(
      cardBoardId(card),
      card.id
    );
    const data = normalize(response?.data || {});
    setAssigneeState(card.id, {
      loading: false,
      loaded: true,
      assignableUsers: data.assignableUsers || [],
    });
    patchCard(card.id, current => ({
      ...current,
      assignees: data.payload || current.assignees || [],
    }));
  } catch (error) {
    const message = apiErrorMessage(
      error,
      t('KANBAN.CARD.LOAD_ASSIGNEES_ERROR')
    );
    setAssigneeState(card.id, { loading: false, error: message });
    useAlert(message);
  }
};

const deleteCard = async card => {
  if (!card || isCardBusy(card)) return false;
  startAction(card.id);
  try {
    await KanbanBoardsAPI.deleteCardById(cardBoardId(card), card.id);
    cards.value = cards.value.filter(
      item => Number(item.id) !== Number(card.id)
    );
    useAlert(t('KANBAN.ACTIONS.REMOVE_CARD_SUCCESS'));
    return true;
  } catch (error) {
    useAlert(apiErrorMessage(error, t('KANBAN.ACTIONS.REMOVE_CARD_ERROR')));
    return false;
  } finally {
    endAction(card.id);
  }
};
const openDeleteConfirm = card => {
  cardToDelete.value = card;
  deleteDialogRef.value?.open();
};
const onOpportunityRemoveCard = card => {
  closeOpportunityPanel();
  openDeleteConfirm(card);
};
const confirmDelete = async () => {
  if (!cardToDelete.value || isDeletingCard.value) return;
  isDeletingCard.value = true;
  const deleted = await deleteCard(cardToDelete.value);
  isDeletingCard.value = false;
  if (deleted) {
    deleteDialogRef.value?.close();
    cardToDelete.value = null;
  }
};

watch([cards, staleCardCount], () =>
  emit('summary', {
    count: cards.value.length,
    staleCount: staleCardCount.value,
  })
);
watch(
  () => props.conversationId,
  () => {
    cancelForm();
    cards.value = [];
    assigneeStates.value = {};
    loadCards();
  }
);
// The boards payload spans the whole account and only the expanded card needs it, so
// a collapsed section pays for its counter with the card request alone.
const hasRequestedBoards = ref(false);
watch(
  () => props.isOpen,
  isOpen => {
    if (!isOpen || hasRequestedBoards.value) return;

    hasRequestedBoards.value = true;
    loadBoards();
  },
  { immediate: true }
);
onMounted(() => {
  emitter.on(BUS_EVENTS.KANBAN_REALTIME_EVENT, handleRealtimeKanbanEvent);
  loadCards();
});
onBeforeUnmount(() => {
  clearTimeout(highlightTimer);
  cardsAbortController.value?.abort();
  boardsAbortController.value?.abort();
  createAbortController.value?.abort();
  emitter.off(BUS_EVENTS.KANBAN_REALTIME_EVENT, handleRealtimeKanbanEvent);
});
</script>

<template>
  <div class="relative p-3 text-sm">
    <p v-if="isLoading && !hasCards" class="mb-0 text-n-slate-11">
      {{ t('CONVERSATION_SIDEBAR.KANBAN.LOADING') }}
    </p>
    <p v-else-if="hasError" class="mb-0 text-n-ruby-11">
      {{ t('CONVERSATION_SIDEBAR.KANBAN.ERROR') }}
    </p>
    <template v-else>
      <p v-if="!hasCards && !isFormOpen" class="mb-3 text-n-slate-11">
        {{ t('CONVERSATION_SIDEBAR.KANBAN.EMPTY') }}
      </p>
      <button
        v-if="!hasCards && !isFormOpen"
        type="button"
        data-testid="kanban-conversation-card-create-empty"
        class="h-9 rounded-md bg-n-brand px-3 text-sm font-medium text-white hover:bg-n-brand/90"
        @click="openForm"
      >
        {{ t('CONVERSATION_SIDEBAR.KANBAN.CREATE') }}
      </button>
      <ul v-if="hasCards" class="m-0 flex list-none flex-col gap-2 p-0">
        <li v-for="card in cards" :key="card.id" class="min-w-0">
          <KanbanConversationCardItem
            :card="card"
            :board="boardForCard(card)"
            :regular-stages="regularStagesFor(card)"
            :is-busy="isCardBusy(card)"
            :is-highlighted="Number(highlightedCardId) === Number(card.id)"
            :is-assignees-loading="assigneeStateFor(card).loading"
            :assignable-users="assigneeStateFor(card).assignableUsers || []"
            @change-status="changeStatus"
            @delete="openDeleteConfirm"
            @load-assignees="loadAssignees"
            @open-details="openDetails"
            @open-move="openMoveDialog"
            @update-assignees="updateAssignees"
            @update-due-date="updateDueDate"
            @update-labels="updateLabels"
            @update-priority="updatePriority"
            @update-stage="updateStage"
          />
        </li>
      </ul>
      <button
        v-if="hasCards && !isFormOpen"
        type="button"
        data-testid="kanban-conversation-card-create-another"
        class="mt-3 text-xs font-medium text-n-brand hover:underline"
        @click="openForm"
      >
        {{ t('CONVERSATION_SIDEBAR.KANBAN.CREATE_IN_ANOTHER_BOARD') }}
      </button>
      <KanbanConversationCardForm
        v-if="isFormOpen"
        :boards="boards"
        :cards="cards"
        :inbox-id="inboxId"
        :default-subject="defaultSubject"
        :is-loading-boards="isLoadingBoards"
        :boards-error="boardsError"
        :is-creating="isCreating"
        :error="createError"
        @cancel="cancelForm"
        @create="createCard"
        @open-existing="emit('open-existing', $event)"
      />
    </template>

    <KanbanCardMoveDialog
      v-if="moveDialogCard"
      :card="moveDialogCard"
      :existing-cards="cards"
      :boards="boards"
      :board="boardForCard(moveDialogCard)"
      :stages="stagesForCard(moveDialogCard)"
      :won-stage-id="Number(boardForCard(moveDialogCard).wonStageId) || null"
      :lost-stage-id="Number(boardForCard(moveDialogCard).lostStageId) || null"
      :inbox-id="cardInboxId(moveDialogCard)"
      :reasons="boardForCard(moveDialogCard).reasons || []"
      :is-moving="moveDialogIsMoving"
      another-board-only
      @close="closeMoveDialog"
      @move="moveCardToBoard"
    />

    <KanbanOpportunityPanel
      v-if="opportunityCard"
      ref="opportunityPanelRef"
      :board-id="cardBoardId(opportunityCard)"
      :card-id="opportunityCard.id"
      :board-name="opportunityBoard.name || ''"
      :board="opportunityBoard"
      :boards="boards"
      :stages="opportunityStages"
      :won-stage-id="Number(opportunityBoard.wonStageId) || null"
      :lost-stage-id="Number(opportunityBoard.lostStageId) || null"
      :lost-reason-required="Boolean(opportunityBoard.lostReasonRequired)"
      :reasons="opportunityBoard.reasons || []"
      :custom-fields="opportunityBoard.customFields || []"
      :move-to-stage="moveToStageFromPanel"
      :has-blocking-dialog="false"
      opened-from-conversation
      @board-changed="onOpportunityBoardChanged"
      @close="closeOpportunityPanel"
      @open-funnel="openOpportunityInFunnel"
      @remove-card="onOpportunityRemoveCard"
      @updated="onOpportunityUpdated"
    />

    <Dialog
      ref="deleteDialogRef"
      type="alert"
      :title="t('CONVERSATION_SIDEBAR.KANBAN.DELETE_CONFIRM_TITLE')"
      :description="t('CONVERSATION_SIDEBAR.KANBAN.DELETE_CONFIRM_DESCRIPTION')"
      :confirm-button-label="
        t('CONVERSATION_SIDEBAR.KANBAN.DELETE_CONFIRM_BUTTON')
      "
      :is-loading="isDeletingCard"
      @confirm="confirmDelete"
    />
  </div>
</template>
