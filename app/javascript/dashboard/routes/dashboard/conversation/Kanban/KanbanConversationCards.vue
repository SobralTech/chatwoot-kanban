<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import camelcaseKeys from 'camelcase-keys';

import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useSlaClock } from 'dashboard/composables/useSlaClock';
import { getCardStatusChangeErrorMessage } from 'dashboard/helper/kanbanCardStatus';
import { apiErrorMessage } from 'dashboard/helper/kanbanApiError';
import { toIso8601 } from 'dashboard/helper/kanbanDueDate';
import { SLA_STALE, stageSlaStatus } from 'dashboard/helper/kanbanStageSla';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import KanbanConversationCardForm from './KanbanConversationCardForm.vue';
import KanbanConversationCardItem from './KanbanConversationCardItem.vue';

const props = defineProps({
  conversationId: {
    type: [Number, String],
    required: true,
  },
});

const emit = defineEmits(['open-existing', 'summary']);
const { t } = useI18n();
const store = useStore();
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
const slaNow = useSlaClock();
let highlightTimer = null;

const inboxId = computed(
  () => currentChat.value?.inbox_id || currentChat.value?.inboxId
);
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
const hasBusyCards = computed(() => busyCardIds.value.size > 0);
const staleCardCount = computed(
  () =>
    cards.value.filter(card => {
      const stage = card.kanbanStage || card.kanban_stage || {};
      return (
        stageSlaStatus({
          stageEnteredAt: card.stageEnteredAt ?? card.stage_entered_at,
          slaHours: stage.slaHours ?? stage.sla_hours,
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
const cardBoardId = card =>
  card.kanbanBoardId ||
  card.kanbanBoard?.id ||
  card.kanban_board_id ||
  card.kanban_board?.id;
const boardStages = board =>
  board?.stagesSummary || board?.stages_summary || [];
const boardForCard = card => {
  const boardId = cardBoardId(card);
  return (
    boards.value.find(board => Number(board.id) === Number(boardId)) ||
    card.kanbanBoard ||
    card.kanban_board ||
    {}
  );
};
const regularStagesFor = card => {
  const board = boardForCard(card);
  const terminalIds = [board.wonStageId, board.lostStageId]
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
const snapshotCard = card => ({
  ...card,
  kanbanBoard: card.kanbanBoard ? { ...card.kanbanBoard } : card.kanbanBoard,
  kanbanStage: card.kanbanStage ? { ...card.kanbanStage } : card.kanbanStage,
  labels: (card.labels || []).map(label => ({ ...label })),
  assignees: (card.assignees || []).map(assignee => ({ ...assignee })),
});
const startAction = cardId => {
  busyCardIds.value = new Set([...busyCardIds.value, Number(cardId)]);
};
const isCardBusy = card => busyCardIds.value.has(Number(card.id));
const setAssigneeState = (cardId, value) => {
  assigneeStates.value = {
    ...assigneeStates.value,
    [cardId]: { ...assigneeStates.value[cardId], ...value },
  };
};
const assigneeStateFor = card => assigneeStates.value[card.id] || {};

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

const runCardAction = async ({ card, optimistic, request, apply, error }) => {
  if (isCardBusy(card)) return;
  const previousCard = snapshotCard(card);
  startAction(card.id);
  optimistic?.();

  try {
    const response = await request();
    apply?.(response);
  } catch (actionError) {
    patchCard(card.id, () => previousCard);
    useAlert(typeof error === 'function' ? error(actionError) : error);
  } finally {
    endAction(card.id);
  }
};

const updateStage = (card, targetStageId) => {
  const board = boardForCard(card);
  const stage = regularStagesFor(card).find(
    item => Number(item.id) === Number(targetStageId)
  );
  if (!board.id || !stage) return;

  runCardAction({
    card,
    optimistic: () =>
      patchCard(card.id, current => ({
        ...current,
        kanbanStageId: stage.id,
        kanbanStage: { ...current.kanbanStage, ...stage },
      })),
    request: () =>
      KanbanBoardsAPI.reorderCardById(board.id, card.id, {
        card: { kanban_stage_id: stage.id, after_card_id: null },
      }),
    apply: response => {
      const updated = normalizeCard(response);
      patchCard(card.id, current => ({
        ...current,
        ...(updated?.id ? updated : {}),
        kanbanStageId: updated?.kanbanStageId ?? stage.id,
        kanbanStage: {
          ...current.kanbanStage,
          ...stage,
          ...(updated?.kanbanStage || {}),
        },
      }));
    },
    error: t('KANBAN.ACTIONS.REORDER_CARD_ERROR'),
  });
};

const changeStatus = (card, { targetStageId, reasonId, reopen }) => {
  const board = boardForCard(card);
  if (!board.id) return;
  const targetStage = boardStages(board).find(
    stage => Number(stage.id) === Number(targetStageId)
  );

  runCardAction({
    card,
    optimistic: () => {
      if (reopen || !targetStage) return;
      patchCard(card.id, current => ({
        ...current,
        kanbanStageId: targetStage.id,
        kanbanReasonId: reasonId || null,
        kanbanStage: { ...current.kanbanStage, ...targetStage },
      }));
    },
    request: () =>
      reopen
        ? KanbanBoardsAPI.reopenCardById(board.id, card.id)
        : KanbanBoardsAPI.updateCardById(board.id, card.id, {
            card: {
              kanban_stage_id: targetStageId,
              kanban_reason_id: reasonId || null,
            },
          }),
    apply: response => {
      const updated = normalizeCard(response);
      const currentStageId =
        card.kanbanStageId ?? card.kanban_stage_id ?? card.kanbanStage?.id;
      const nextStageId =
        updated?.kanbanStageId ?? (reopen ? currentStageId : targetStageId);
      const nextStage =
        boardStages(board).find(
          stage => Number(stage.id) === Number(nextStageId)
        ) || targetStage;
      patchCard(card.id, current => ({
        ...current,
        ...(updated?.id ? updated : {}),
        kanbanStageId: nextStageId,
        kanbanReasonId:
          updated?.kanbanReasonId ?? (reopen ? null : reasonId || null),
        kanbanStage: {
          ...current.kanbanStage,
          ...nextStage,
          ...(updated?.kanbanStage || {}),
        },
      }));
    },
    error: actionError =>
      getCardStatusChangeErrorMessage(actionError, { reopen, t }),
  });
};

const updatePriority = (card, value) => {
  const board = boardForCard(card);
  if (!board.id) return;
  runCardAction({
    card,
    optimistic: () =>
      patchCard(card.id, current => ({ ...current, priority: value || '' })),
    request: () =>
      KanbanBoardsAPI.updateCardDetailsById(board.id, card.id, {
        priority: value || null,
      }),
    apply: response => {
      const updated = normalizeCard(response);
      if (updated?.priority !== undefined) {
        patchCard(card.id, current => ({
          ...current,
          priority: updated.priority,
        }));
      }
    },
    error: t('KANBAN.CARD.PRIORITY_UPDATE_ERROR'),
  });
};

const updateDueDate = (card, value) => {
  const board = boardForCard(card);
  if (!board.id) return;
  const dueAt = toIso8601(value);
  runCardAction({
    card,
    optimistic: () => patchCard(card.id, current => ({ ...current, dueAt })),
    request: () =>
      KanbanBoardsAPI.updateCardDetailsById(board.id, card.id, {
        due_at: dueAt,
      }),
    apply: response => {
      const updated = normalizeCard(response);
      if (updated?.dueAt !== undefined) {
        patchCard(card.id, current => ({ ...current, dueAt: updated.dueAt }));
      }
    },
    error: t('KANBAN.CARD.DUE_DATE_UPDATE_ERROR'),
  });
};

const labelsForTitles = titles =>
  titles.map(
    title =>
      (accountLabels?.value || []).find(label => label.title === title) || {
        title,
      }
  );
const updateLabels = (card, titles) => {
  const board = boardForCard(card);
  if (!board.id) return;
  runCardAction({
    card,
    optimistic: () =>
      patchCard(card.id, current => ({
        ...current,
        labels: labelsForTitles(titles),
      })),
    request: () => KanbanBoardsAPI.updateCardLabels(board.id, card.id, titles),
    apply: response => {
      const labels = normalize(response?.data?.payload || response?.data || []);
      if (Array.isArray(labels)) {
        patchCard(card.id, current => ({ ...current, labels }));
      }
    },
    error: t('CONTACT_PANEL.LABELS.CONVERSATION.ERROR'),
  });
};

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

const updateAssignees = (card, ids) => {
  const board = boardForCard(card);
  if (!board.id) return;
  const state = assigneeStateFor(card);
  const users = state.assignableUsers || [];
  runCardAction({
    card,
    optimistic: () =>
      patchCard(card.id, current => ({
        ...current,
        assignees: ids.map(
          id =>
            users.find(user => Number(user.id) === Number(id)) ||
            current.assignees?.find(
              assignee => Number(assignee.id) === Number(id)
            ) || { id }
        ),
      })),
    request: () => KanbanBoardsAPI.updateCardAssignees(board.id, card.id, ids),
    apply: response => {
      const data = normalize(response?.data || {});
      patchCard(card.id, current => ({
        ...current,
        assignees: data.payload || [],
      }));
      setAssigneeState(card.id, {
        loaded: true,
        assignableUsers: data.assignableUsers || users,
      });
    },
    error: t('KANBAN.CARD.ASSIGN_ERROR'),
  });
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

watch(
  [cards, staleCardCount],
  () =>
    emit('summary', {
      count: cards.value.length,
      staleCount: staleCardCount.value,
    }),
  { immediate: true }
);
watch(
  () => props.conversationId,
  () => {
    cancelForm();
    assigneeStates.value = {};
    loadCards();
  }
);
onMounted(() => {
  emitter.on(BUS_EVENTS.KANBAN_REALTIME_EVENT, handleRealtimeKanbanEvent);
  loadBoards();
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
  <div class="p-3 text-sm">
    <p v-if="isLoading" class="mb-0 text-n-slate-11">
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
